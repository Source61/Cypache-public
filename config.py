# Required arguments

wwwDir = b"www"
appsDir = b"apps"

# Determines if the apps directory will contain the sub-directories controllers, models, views, or contains only applications and paths to them (False is equivalent to controllers only without any of the MVC sub-directories)
#mvcPattern = True

# If not empty: sends all requests except for those that matches with paths in wwwDir (HTML and binary blobs) to this appsDir path e.g. b"index.py" (full path becomes $appsPath/index.py with mvcPattern disabled)
rewritePathTo = b""


# Optional arguments

# Defaults to []
indexes = [b"index.py", b"index.html"]

# Defaults to ulimit -n, -1 is max (higher values potentially increases performance, but uses up more file descriptors)
maxFds = -1

# Defaults to value in const.pyx (currently 10000). Higher values potentially increases performance but also increases memory usage. 10K is negligible memory footprint.
maxFilepaths = 10000