import
    os, osproc, strutils, terminal

const usage_text: string = "\ngin [options] PATTERN [PATH ...]\n\nValid options:\n-A,--after-context <arg>\tprints the given number of following lines for each match\n-B,--before-context <arg>\tprints the given number of preceding lines for each match\n-c,--color\t\t\tprints with colors, highlighting the matched phrase in the output\n-C,--context <arg>\t\tprints the number of preceding and following lines for each match.\n-h,--hidden\t\t\tsearch hidden files and folders\n   --help\t\t\tprints this message\n-i,--ignore-case\t\tsearch case insesitive\n   --no-heading\t\t\tprint a single line inclusing the filename for each match, instead of grouping matches by file\n   --display-skipped-files\tinforms about skipped non-text files"
#Read parameters
var
    context_before: int = 0
    context_after: int = 0
    color: bool = false
    hidden_files: bool = false
    case_sensitive: bool = true
    heading: bool = true
    display_skipped_files = false
    pattern: string = ""
    paths: seq[string]

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

            pattern = params[i]

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
if pattern.len < 1: # Check if pattern was provided
    printHelp("No pattern provided.")
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

proc findIndices(line: string): seq[int] =
    var indices: seq[int]
    for i in 0 .. line.len - pattern.len:
        if pattern == substr(line, i, i + pattern.len - 1):
            indices.add(i)
    return indices

proc formatPatternInLine(line: string): string =
    if case_sensitive:
        return replace(line, pattern, by = ansiForegroundColorCode(fgRed) & pattern & ansiForegroundColorCode(fgDefault))
    else:
        let indices = findIndices(toLowerAscii(line))
        var formatted_text: string
        var last_index = 0
        if indices.len < 1:
            return "Error"
        for index in indices:
            if index == 0: # If pattern found right at the start
                formatted_text = ansiForegroundColorCode(fgRed) & substr(line, index, index + pattern.len - 1) & ansiForegroundColorCode(fgDefault)
                last_index = pattern.len
                continue
            formatted_text = formatted_text & substr(line, last_index, index - 1) & ansiForegroundColorCode(fgRed) & substr(line, index, index + pattern.len - 1) & ansiForegroundColorCode(fgDefault)
            last_index = index + pattern.len
        if indices[indices.len - 1] < line.len - pattern.len: # If there is still text after the last pattern
            formatted_text = formatted_text & substr(line, last_index)
        return formatted_text


proc printResult(file: string, line_count: int, line_indices: seq[int]) =
    let path_shortened = if file.startsWith(working_directory): substr(file, working_directory.len + 1) else: file
    
    # print_lines_indixes are all lines that will be printed (the lines with the pattern and the additional context)
    var print_lines_indices: seq[int]
    if context_before == 0 and context_after == 0: # If no context lines are expected the costly for loop in the "else block" can be skipped
        print_lines_indices = line_indices
    else:
        for line_index in line_indices:
            # Before context lines
            if context_before > 0:
                for i in line_index - context_before .. line_index - 1:
                    if i >= 0 and not print_lines_indices.contains(i):
                        print_lines_indices.add(i)
            # The actual line with the pattern
            if not print_lines_indices.contains(line_index):
                print_lines_indices.add(line_index)
            # After context lines
            if context_after > 0:
                for i in line_index + 1 .. line_index + context_after:
                    if i < line_count and not print_lines_indices.contains(i):
                        print_lines_indices.add(i)
            
    echo "" # New line for better readability
    if heading:
        echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path_shortened

    var line_index = 0 # The index of each line in the following loop
    for line in lines file:
        if print_lines_indices.contains(line_index): # Checks if the current line is to be printed

            if heading: # Presentation with heading
                if line_indices.contains(line_index): # If line contains pattern
                    echo (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), ":", (if color: formatPatternInLine(line) else: line)
                else: # If context line
                    echo (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), "-", line

            else: # Presentation without heading
                if line_indices.contains(line_index): # If line contains pattern
                    echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path_shortened, ansiForegroundColorCode(fgDefault), ":", (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), ":", (if color: formatPatternInLine(line) else: line)
                else: # If context line
                    echo (if color: ansiForegroundColorCode(fgMagenta) else: ""), path_shortened, ansiForegroundColorCode(fgDefault), "-", (if color: ansiForegroundColorCode(fgGreen) else: ""), (line_index + 1), ansiForegroundColorCode(fgDefault), "-", line
        
        line_index = line_index + 1

# Checks if the file has the pattern in its content
proc checkFile(file: string, pattern: string) =
    # Check if the provided file is a text file
    let output = execProcess("file --mime \"" & file & "\"")
    let output_seq = output.split(' ')
    if not output_seq[output_seq.len - 2].startsWith("text"): # The second to last block of this output starts with "text", if the file has text content
        if display_skipped_files:
            echo ansiForegroundColorCode(fgDefault), (if file.startsWith(working_directory): substr(file, working_directory.len + 1) else: file) & ansiForegroundColorCode(fgDefault) & " is not a text file or has no content. Skipped", ansiForegroundColorCode(fgDefault)
        return
    var indices: seq[int] # A squence of indices of the lines where the pattern has been found

    var line_index = 0 # The index of each line in the following loop
    for line in lines file:
        if contains(if case_sensitive: line else: toLowerAscii(line), if case_sensitive: pattern else: toLowerAscii(pattern)):
            indices.add(line_index)
        line_index = line_index + 1
    if indices.len > 0:
        printResult(file, line_index, indices) # line_index is the amount of lines of the file
    

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
