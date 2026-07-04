

#-------------------------------------------------------------------------------
#
# gh-api()
#
# Make an authenticated request to the GitHub API. Pagination is automatic.
# All responses and headers are saved to a folder; the folder path is
# printed to stdout.
#
#
# flags
#       [--data]           POST data
#       [--output]         Specify output          
#       [--token]          GitHub API token
#
# --output + --remote-name: last one wins (curl allows, does not define)
#
# positional args
#
#	$1	url
#
# Response shape auto-detection (first page):
#   type: array          -> key = "."
#   object + total_count -> key = array field
#   otherwise            -> key = ".items"
#
gh-api ()
{
}



#-------------------------------------------------------------------------------
#
# gh-api_ ()
#
# Make an authenticated request to the GitHub API. Pagination is automatic.
# All responses and headers are saved to a folder; the folder path is
# printed to stdout.
#
# The output folder contains:
#   data.json                                 Merged items across all pages
#   $filename                                 Raw response (non-paginated)
#   $(filename minus ext).headers.txt         Response headers (non-paginated)
#   $filename.nnnnnn                          Raw response page N (paginated)
#   $(filename minus ext).headers.txt.nnnnnn  Headers page N (paginated)
#
# flags
#
# positional args
# 	$1		  assoc array of arguments
#
#
# assoc array elements
#       [accept]         Accept header value
#       [data]           POST data
#       [output]         Full path to output file
#       [output-dir]     Output folder
#       [per-page]       Results per page (max 100)
#       [remote-name]    Derive filename from Content-Disposition
#       [token]          GitHub API token
#
# Response shape auto-detection (first page):
#   type: array          -> key = "."
#   object + total_count -> key = array field
#   otherwise            -> key = ".items"
gh-api_ ()
{
}


#-------------------------------------------------------------------------------
#
# gh-parse-args()
#
# translate the flags and positional args for a github API request into an
# argmap of keys and values for consumption by a github kernel function, eg
# gh-api_.
#
# flags 
#       [--accept]         Accept header value
#       [--data]           POST data
#       [--output]         Full path to output file
#       [--output-dir]     Output folder
#       [--per-page]       Results per page (max 100)
#       [--remote-name]    Derive filename from Content-Disposition
#       [--token]          GitHub API token
#
# positional args
#       $1                 nameref of associative array to populate
#       $2 	           path of url for GitHub api endpoint
#
# returns
#       argmap             the incoming nameref which is populated with args,
#                          from both flags and positional args
#
gh-parse-args ()
{
}


#-------------------------------------------------------------------------------
#
# gh-unparse-curl-args()
#
# translate an assoc array into a series of flags and positional args that can
# be used to call curl. 
#
# flags
# 	none
#
# positional args
# 	$1	nameref to an assoc array of argument data
# 	$2	nameref to an array for receiving curl flags + values
# 	$3	nameref to an array for 	
#
gh-unparse-curl-args ()
{
}

# The output folder contains:
#   data.json                                 Merged items across all pages
#   $filename                                 Raw response (non-paginated)
#   $(filename minus ext).headers.txt         Response headers (non-paginated)
#   $filename.nnnnnn                          Raw response page N (paginated)
#   $(filename minus ext).headers.txt.nnnnnn  Headers page N (paginated)
