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
1. Kernel funcs take a nameref to an argmap as their only parameter
    - This is the interface to the function
    - Analagous to named-paramters only
    - Caller populates the argmap with flag values and positional arguments
        - 'What' is defined by kernel func
        - 'How', eg flag, posarg, or both, is defined by caller
1. Kernel / user interactions
    - User functions can call kernel functions
    - Kernel functions can call kernel functions
    - Neither can call user functions

### example: gh-curl, gh-curl_, and ghr-list

#### gh-curl_
`gh-curl_` is a kernel function, which makes sense since it's the most important github function. It takes a good number of arguments - a combo of flags commonly used by curl, and flags commonly used by the GitHub REST API. That roughly looks like this as of this writing
```
#       [output]         Full path to output file
#       [output-dir]     Output folder
#       [remote-name]    Derive filename from Content-Disposition
#       [accept]         Accept header value
#       [data]           POST data
#       [per-page]       Results per page (max 100)
#       [token]          GitHub API token
```

Most callers will only use a subset of these commands. The corresponding user function should use them all.

The beginning of the function looks something like this
```
    # shellcheck disable=SC2016
    (( $# == 2 )) || { printf 'Usage: getVmName infovar $user\n' >&2; return 1; }
    local -n appMap=$1
    local -n flags args
    local accept data output output_dir per_page remote_name token
    gh-curl-args argmap args
    curl "$args[@]"
```

`gh-curl_` ultimately needs to call curl, and curl takes flags and positional args. Mostly it takes flags; the positional args it takes is a sequence of URLs. `gh-curl-args` translates from an argmap back into a series of cmdline args for `curl`. 

#### gh-curl
gh-curl is the user function that invokes the gh-curl_ kernel function. The beginning of the function turns flags and args into an argmap
by calling gh-parse-args

    # argmap   nameref to an array to receive flags and positional arguments
    gh-parse-args argmap "$@"
    gh-curl_ argmap

At the end of this, gh-curl has sorted out all its args and can call gh-curl_, possibly after enriching argmap with positional argument data

For more details consult the gh-curl.md document

#### gh-list
`gh-list` has a simple interface. All it needs is a org, a repo and an optional token.

