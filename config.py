# Required argument
wwwDir = b"./www"

# Optional argument; defaults to []
indexes = [b"index.html", b"index.py"]

# Optional argument; defaults to ulimit -n, -1 is max
maxFds = -1

# Optional argument; defaults to value in const.pyx (currently 10000)
maxFilepaths = 10000