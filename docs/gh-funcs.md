### --output

curl provides 3 flags for determining where to download data: --output, --output-dir, and --remote-name. Their responsibilties overlap, and specifying more than one of them in a manner that conflicts is both legal and undefined.

gh-api will take a single flag called --output which will have the following meanings

flag value      meaning                 curl flags
(absent)        pwd + remote name       --remote-name
rel dirname     $dir + remote name      --output-dir or --output-dir $(pwd)/$dir (not sure which) --remote-name
rel filename    pwd + $file             --output $file or --output "$(pwd)/$file" (not sure which)
abs dirname     $dir + remote name      --output-dir $dir  --remote-name
abs path        $path                   --output "$path" 

In theory, anything that achieves these --output semantics is ok -- it shouldn't matter if its curl flags or not. However, since curl has the flags, im not sure what would be a better approach

#### dir detection
paths ending in slash are explicitly folders
paths not ending in slash should be treated as folders if they are in fact folders, trailing slash or not
it's not ok to classify an --output value is a file, when it is in fact a dir, and then fail the download

#### symlinks
no special handling. let curl deal with it
@note if we need to change this with either a passthru flag or hardwired opinionated behavior, we can make that change later. Right now there's no demand for either and no intuition over what The Right Thing is.

#### collision detection etc (files that exist, dir that dont)
gh-api will handle 'problem' --output values according to a 'leave no trace' philosophy
- if a file exists, fail: dont clobber it
- if a folder doesnt exist, fail: dont create it
user functions can provide their own semantics here. if a lot of user-functions are written and are duplicating a lot of code, that can drive the adoption of configuring collision etc detection behavior in gh-api, but for now those will be userfunc concerns 

### user functions (ufs) and kernel functions (kfs)

Parsing is a Hard Problem in bash. It's Harder when functions that take lots of flags, and Even Harder when functions that take lots of flags all other functions that take lots of flags. Github functions fall into this catebory. There are central functions that accept many flags, most of which are optional, and user-facing edge functions form callchains with these core functions. Things could get very ugly.

To avoid turning this into a flag-parsing effort rather than a delivering-features issue, care needs to be taken in choosing the right development model and idioms.

1. Arguments only get parsed once.
1. The functions that are invoked with parsed args are called user functions
1. User functions parse flags and positional args into an associative array
    - names
        - flags come with a name already that's a good hint
        - positional args require coming up with a name
        - end of the day, it comes down to what the downstream function is expecting
        - 'downstream function'?!? read on!
    - values
        - all values in bash are strings so no processing required
        - boolean flags are handled nicely by an argmap
        - absence/presence are also handled nicely by an argmap
        - does a missing positional argument = missing argmap key? or an argmap entry explicitly indicating absence. Up to downstream.
1. Once a user function has its argmap setup, it calls a downstream function called a kernel function
1. Kernel function names end with a trailing underscore. This clearly disambiguates them from user functions.
1. Kernel functions will have coresponding user functions
    - user function name = kernel function name minus the trailing underscore
    - these user funcs serve as nice references for how to call the kernel func
1. Kernel funcs do NOT parse flags or args
1. Kernel funcs take a nameref to an flagmap for most of their args
    - This is the interface to the function
    - Analagous to named-paramters only
    - Caller populates the argmap with flag values and positional arguments
        - 'What' is defined by kernel func
        - 'How', eg flag, posarg, or both, is defined by caller
1. Kernel / user interactions
    - User functions can call kernel functions
    - Kernel functions can call kernel functions
    - Neither can call user functions
1. Never pass a nameref to another function.  When a function receives a
   nameref, it uses the original variable name (the string `$1`, `$2`, etc.)
   when passing that reference downstream.  This avoids double indirection
   and the "circular name reference" warnings that come with it.
    - Kernel function does:      `local -n _flagMap=$1`
    - Downstream call does:      `some-kf "$1" _otherFlags`
    - NOT:                       `some-kf _flagMap _otherFlags`

### example: gh-api, gh-api_, and ghr-api

#### gh-api_

Receives a flagMap (associative array) and a urlPath.  All HTTP calls go
through this function.  Constructs curl flags via gh-unparse-curl-args,
resolves the --output specifier via resolve-output-spec, adds standard
curl infrastructure flags (--fail-with-body --location --silent), and
executes the curl call against https://api.github.com/$urlPath.

flagMap keys:
  [accept]       Accept header value (omitted if not set — curl default)
  [data]         POST data
  [output]       Output specifier — resolved by resolve-output-spec
  [per-page]     Appended as ?per_page=N to the URL
  [token]        Authorization: Bearer header

#### gh-api

User function.  Parses CLI flags via gh-parse-args, enriches the flagMap,
then calls gh-api_ with the flagMap and a urlPath.

flags:
  [--data]       POST data
  [--output]     Output specifier (see --output section above)
  [--per-page]   Results per page
  [--token]      GitHub API token

#### gh-list
`gh-list` has a simple interface. All it needs is a org, a repo and an optional token.

### Helper functions

#### gh-parse-args

Parses CLI flags and positional args into a flagMap (associative array)
and a posargs (indexed array).  Flags and positional args can be
interleaved.  Anything starting with -- is a flag; anything else is a
positional arg.

Known flags:
  --accept, --data, --extract, --output, --per-page, --token,
  --label, --platform, --version, --workflow  (all value flags)
  (boolean flags: none currently)

  --                 Terminator.  Everything after -- is a positional arg,
                     even if it starts with --.
  --* (unknown)      Error: "Unknown flag" with non-zero exit.

Output:
  flagMap     flag values indexed by flag name (without leading --)
  posargs     positional arguments in order

#### gh-unparse-curl-args

Translates a flagMap (from gh-parse-args) into an array of curl flags.
Does not construct the URL — the caller provides it separately.

flagMap keys:
  [accept]   → --header "Accept: ..."
  [token]    → --header "Authorization: Bearer ..."
  [data]     → --data "..."

Output:
  curlFlags   array of curl flags and their values

#### resolve-output-spec

Translates the --output flagMap value into the corresponding curl output
flags.  See the ### --output section above for semantics.

  (empty)         → --remote-name                       (default)
  ends with /     → --output-dir "$path" --remote-name  (directory mode)
  existing dir    → --output-dir "$path" --remote-name  (directory mode, no slash)
  existing file   → error (no clobber)
  otherwise       → --output "$path"                    (file mode)

Fails with non-zero and an error message if the target directory doesn't
exist or the target file already exists (leave no trace philosophy).
