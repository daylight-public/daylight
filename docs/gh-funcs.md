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

### example: gh-api, gh-api_, and ghr-api

#### gh-api_

#### gh-api

#### gh-list
`gh-list` has a simple interface. All it needs is a org, a repo and an optional token.

### Helper functions
