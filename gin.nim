import
    os, osproc, sets, strutils, terminal, regex

const usage_text: string = "\ngin [options] PATTERN [PATH ...]\n\nValid options:\n-A,--after-context <arg>\tprints the given number of following lines for each match\n-B,--before-context <arg>\tprints the given number of preceding lines for each match\n-c,--color\t\t\tprints with colors, highlighting the matched phrase in the output\n-C,--context <arg>\t\tprints the number of preceding and following lines for each match.\n-h,--hidden\t\t\tsearch hidden files and folders\n   --help\t\t\tprints this message\n-i,--ignore-case\t\tsearch case insesitive\n   --no-heading\t\t\tprint a single line inclusing the filename for each match, instead of grouping matches by file\n   --display-skipped-files\tinforms about skipped non-text files"
const buffer_size = 4096 # amount of lines the buffer can hold

#Read parameters
var
    context_before: int = 0
    context_after: int = 0
    color: bool = false
    hidden_files: bool = false
    case_sensitive: bool = true
    heading: bool = true
    display_skipped_files = false
    pattern: Regex2
    pattern_string: string = ""
    paths: seq[string]
    lines_printed: seq[int] # a sequence of lines already printed
    heading_printed: bool = false # if a heading has been printed for the current file already

var buffer_count = 0 # how many buffers the current file used yet
var buffer_index = 0 # index of the current line in the buffer
var line_buffer: array[buffer_size, string]
var marked_after_context_lines: int # the amount of after context lines marked for printing

let working_directory = getAppDir()

proc printHelp(errorMsg: string) =
    echo ansiForegroundColorCode(fgCyan), "Gin", ansiForegroundColorCode(fgDefault), " - Grep in Nim", ansiForegroundColorCode(fgRed), (if errorMsg.len > 0: "\nError: " & errorMsg else: ""), ansiForegroundColorCode(fgYellow), "\n\nUsage: ", ansiForegroundColorCode(fgDefault), usage_text
    if errorMsg.len > 0:
        quit()

# Reading parameters
# Check amount of parameters
let param_count: int = paramCount()
if param_count < 1:
    printHelp("")
    quit()

let params: seq[string] = commandLineParams()
var current_param_is_value = false # This variable signals if the i in the following loop is a value related to the prior parameter
for i, p in params:
    case p
    of "-A", "--after-context":
        if i + 1 < param_count: # Check if this parameter has a value
            try: # Check if provided value is valid
                context_after = parseInt(params[i+1])
                current_param_is_value = true
            except ValueError:
                printHelp("Invalid after-context value.")
        else:
            printHelp("No value for the parameter after-context was provided.")
    of "-B", "--before-context":
        if i + 1 < param_count: # Check if this parameter has a value
            try: # Check if provided value is valid
                context_before = parseInt(params[i+1])
                current_param_is_value = true
            except ValueError:
                printHelp("Invalid before-context value.")
        else:
            printHelp("No value for the parameter before-context was provided.")
    of "-C", "--context":
        if i + 1 < param_count: # Check if this parameter has a value
            try: # Check if provided value is valid
                context_after = parseInt(params[i+1])
                context_before = context_after
                current_param_is_value = true
            except ValueError:
                printHelp("Invalid context value.")
        else:
            printHelp("No value for the parameter context was provided.")
    of "-c", "--color":
        color = true
    of "--help":
        printHelp("")
    of "-h", "--hidden":
        hidden_files = true
    of "-i", "--ignore-case":
        case_sensitive = false
    of "--no-heading":
        heading = false
    of "--display-skipped-files":
        display_skipped_files = true
    else:
        if p.startsWith('-'):
            printHelp("Unknown parameter: " & params[i])
        else: # The first parameter not starting with "-" is the pattern
            if current_param_is_value: # If p is a value related to the last p it is neither a pattern nor a path in the next step
                current_param_is_value = false
                continue

            pattern_string = params[i]

            if i + 1 < param_count: # Every parameter after the pattern is considered a file or directory to be searched
                paths = params[i + 1 ..< param_count]
                
                # Transform relative paths to absolute paths
                for i, path in paths:
                    if not path.startsWith('/'): # Check if it is a relative path
                        paths[i] = (working_directory & "/" & path) # Transform to absolute path
                    #Check file's existance
                    if not (fileExists(paths[i]) or dirExists(paths[i])):
                        printHelp(paths[i] & " does not exist.")

            break # After the pattern (and paths) were found, the loop should stop
if pattern_string.len < 1: # Check if pattern was provided
    printHelp("No pattern provided.")
pattern = re2(if pattern_string.contains('('): pattern_string else: "(" & pattern_string & ")")
if paths.len < 1: # If no file or directory to be searched is provided, the current directory shall be used instead
    paths.add(getAppDir())


proc isHiddenFile(file: string): bool =
    var lastIndex = -1 # The last index of '/' in the filepath
    # It would be more efficient to start at the end but I didn't find a way to reverse the direction of the loop
    for i, c in file:
        if c == '/':
            lastIndex = i
    if file[lastIndex+1] == '.':
        return true
    return false


proc formatPatternInLine(line: string): string =
    return line.replace(pattern, ansiForegroundColorCode(fgRed) & "$#" & ansiForegroundColorCode(fgDefault))

# Prints the line
proc printLine(line_index: int, line: string, path: string) =
    if heading and not heading_printed:
        echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path, ansiForegroundColorCode(fgDefault)
        heading_printed = true

    if not lines_printed.contains(line_index):
        if heading: # Presentation with heading
            if regex.contains(line, pattern): # If line contains pattern
                echo (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), ":", (if color: formatPatternInLine(line) else: line)
            else: # If context line
                echo (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), "-", line

        else: # Presentation without heading
            if regex.contains(line, pattern): # If line contains pattern
                echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path, ansiForegroundColorCode(fgDefault), ":", (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), ":", (if color: formatPatternInLine(line) else: line)
            else: # If context line
                echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path, ansiForegroundColorCode(fgDefault), "-", (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), "-", line

        lines_printed.add(line_index)

proc checkBuffer(path: string) =
    # Check lines in buffer for the pattern
    for i, bf in line_buffer[0 .. buffer_index]: # i=loopindex, bf=bufferline
        # print after context lines marked in a past loop cycle
        if marked_after_context_lines > 0 and i < buffer_size and bf.len > 0:
            printLine(i + (buffer_size * buffer_count), bf, path)
            marked_after_context_lines -= 1

        # if line contains regex
        if not lines_printed.contains(i) and regex.contains(bf, pattern):
            # if before context lines are requested
            if context_before > 0:
                # if context lines are not in the current buffer
                if i - context_before < 0:
                    # old buffer (there is only one buffer so old buffer refers to the elements at the end of the buffer where the values of "the old buffer" are still)
                    if buffer_count > 0: # checks if there even is an old buffer
                        for j, cl in line_buffer[buffer_size + (i - context_before) .. buffer_size - 1]: # j=loopindex, cl=contextline
                            printLine(i - context_before + j + (buffer_size * buffer_count), cl, path)
                    # current buffer
                    for j, cl in line_buffer[max(i - context_before, 0) .. i - 1]: # j=loopindex, cl=contextline
                        printLine(i - context_before + j + (buffer_size * buffer_count), cl, path)
                    
                # if context lines are only in the current buffer
                else:
                    # print context lines
                    for j, cl in line_buffer[i - context_before .. i - 1]: # j=loopindex, cl=contextline
                        printLine(i - context_before + j + (buffer_size * buffer_count), cl, path)
            
            # Print the current line (with the pattern)
            printLine(i + (buffer_size * buffer_count), bf, path)

            # if after context lines are requested
            if context_after > 0:
                marked_after_context_lines = context_after


# Checks if the file has the pattern in its content
proc checkFile(file: string, pattern: Regex2) =
    # Check if the provided file is a text file
    let output = execProcess("file --mime \"" & file & "\"")
    let output_seq = output.split(' ')
    if not output_seq[output_seq.len - 2].startsWith("text"): # The second to last block of this output starts with "text", if the file has text content
        if display_skipped_files:
            echo ansiForegroundColorCode(fgDefault), (if file.startsWith(working_directory): substr(file, working_directory.len + 1) else: file) & ansiForegroundColorCode(fgDefault) & " is not a text file or has no content. Skipped", ansiForegroundColorCode(fgDefault)
        return

    let path_shortened = if file.startsWith(working_directory): substr(file, working_directory.len + 1) else: file
    heading_printed = false
    marked_after_context_lines = 0

    for line in lines file:
        # write into the buffer
        line_buffer[buffer_index] = line
        # check if buffer is full
        if buffer_index == buffer_size - 1:
            checkBuffer(path_shortened)

            # new buffer
            buffer_count += 1
            buffer_index = 0
        
        buffer_index += 1
    checkBuffer(path_shortened)
    

# Browse the provided files and directories recursively
proc checkFiles(filePaths: seq[string]) =
    var
        files: seq[string]
        directories: seq[string]
    # Split the provided paths into files and directories (because all files in the current directory should be checked first before the directories are searched recusively. Uppermost level first, then second, then third, ...)
    for filePath in filePaths:
        case getFileInfo(filePath, true).kind
        of pcFile:
            files.add(filePath)
        of pcDir:
            directories.add(filePath)
        else: discard
    # Check each file for the pattern
    for f in files:
        checkFile(f, pattern)
    # Check directories for more files/directories
    if directories.len > 0:
        for d in directories:
            var recFiles: seq[string]
            for kind, path in walkDir(d):
                case kind:
                of pcFile, pcDir:
                    # Only add hidden files if option is set
                    if hidden_files:
                        recFiles.add(path)
                    elif not isHiddenFile(path):
                        recFiles.add(path)
                else: discard
            if recFiles.len > 0:
                checkFiles(recFiles)


checkFiles(paths)
