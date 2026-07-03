### specs for gh-curl

#### pagination
gh-curl will support pagination for all endpoints.
The GitHub REST API has a standard schema for indication data is paginated, and how to get the next page
    - data type: .type field (array, object, etc)
    - data element: not sure, i think it's just whatever element appears in required elements, if any, that is not total_count. Possibly a challenge to be machine readable.
    - default data element: '.items' (true for arrays)
    - incomplete data: incomplete_results element (/search endpoints only) or existence of link header
    - next url: available in link_header

#### file folder and names
- the user has 3 optional flags at their disposal, which match the curl flags for the same purpose
    - --output: full path to output
    - --output-dir: folder for output
    - --remote-name: respect the Content-Disposition header for the filename
- We want the output of gh-curl to be a path to a folder containing the files gh-curl created
    - folder-name
        - --output/--output-dir: repect the user's specification
        - otherwise: create a tempfile
            - prefix based on urlPath
            - skip the portion of the path up to but excluding org and repo
            - replace / in the path with .
            - example: /repos/$org/$repo/releases => $org.$repo.releases
    - file-names
        - data-file: always data.json
        - non-paginated
            -- user-specified (--output)
                - header file: $filename.headers.txt
                - response file: $filename
            -- not user-specified (no --output and/or --remote-name)
                - header file: $contentDisposition.headers.txt
                - response file: $contentDisposition
        - paginated
            -- user-specified (--output)
                - header files: $filename.headers.txt.nnnnnn
                - response files: $filename.nnnnnn
            -- not user-specified (no --output and/or --remote-name)
                - header files: $contentDisposition.headers.txt.nnnnnn
                - response files: $contentDisposition.nnnnnn
- chicken-and-egg-problem
    - our filenames depend on whether or not the results are paginated
    - pagination is defined by looking at elemnts in the output
        - type:
        - incomplete_results:
        - existince of link_header
    - If our filename depends on content, and we don't know the content till we download it, what do we call the file?
        - answer:
            - download file and headers to a temporary file or files
            - also download to a temp-folder even if the user specifies a folder
        - dont download to the download-folder directly, but in a sibling
        - mv file(s) download folder when we're done downloading it and we know the filename
        - if caller specified a folder with --output or--output-dir, move the tmp download folder to the user specified folder
            - incremental progress opaque to user
            - however, they can watch for the folder they specified and when they see it for the first time it's fully populated for clean 'edge-triggering'
        - naming convention
            - folder as specified above, based on url path
            - headers file: $folder.headers.txt
            - response file: $folder.response
            - these are siblings of the tmp folder. $folder.headers.txt != $folders/headers.txt
        - on every download, mv header and response files into tempfolder
            - rename accorinding to content-disposition rules
            - add page number to name if paginated
        - after all downloads
            - generate data.json from contanation of all respones + jq 'add'
            - if user specified a folder, mv tmp folder to the user's folder
                - the user folder might exist
                - if so, mv contents to new folder, clobbering if necessary
- The check and egg problem has curl flag implications
    - We still want to honor --output, --output-dir, and --remote-name and handle them like curl
    - However we are no longer passing them to curl because we are doing out own folder+file names
    - We need to emulate curl ourselves
    - corner cases: --output + --remote-name
        - curl allowed
        - curl does not define
        - next best thing: last one wins
- Always use Content-Disposition to determine filename
    - In theory we know it on first download
    - But we don't have a hard guarantee it won't change
    - And we have the header on every request anyway
    - So just use it every time
    - Besides, it means we don't get the file name one way on first download and another way the rest of the time.

        
Header filename is $(filename minus extension).headers.txt.
If data is paginated, write to $filename.nnnnnn, where filename is the filename determined as above, and nnnnnn is a seequence from 000000-999999
Header files will be named similiarly under pagination
The folder is --output-dir if specified. If not, generate a tmpfile name with a prefix based on the urlpath. Drop the portion of the path up to org/repo, and convert / in the remaining path to . (period).
All data gets concatenated into a single file named data.json in the tempfolder.
- concatenation is done by using the self-describing fields in the response to get the data item
- The file needs to be valid json. I think jq 'add' with multiple files achieves this.

#### general goals and rules
We do not want to lose any data
We want to capture actual responses, actual headers via --dump-header, plus a contenation of all data in data.json
- data.json is what they probably want
- all headers and responses are avilable if necessary
- Don't Be Lossy
    - don't overwrite files in a loop
    - don't remove tmp files or folders
    - we want to save everything for proper post mortem analysis if desired.


