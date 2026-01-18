# m2a.sh

A bash script to process files generated from a source file (typically named `m`), organize them by date, and merge them into size-constrained monthly batches.

## Overview

`m2a.sh` automates processing of files derived from a source file (specified via `-i`). It:
1. Generates output files using `email.py`
2. Manages Git repository state in the source file's directory
3. Organizes generated files by year-month
4. Merges files into monthly batches with a maximum size of 9.5MiB
5. Stops processing when encountering files older than a specified date

## Prerequisites

- Bash shell environment
- Python 3.x (for running `email.py`)
- Git (for repository operations)
- `email.py` (companion script for file generation)

## Usage

### Step 1: Download Kernel Mailing List Repository from EROL

First, clone the target kernel mailing list repository from [https://erol.kernel.org/](https://erol.kernel.org/). EROL hosts repositories for various kernel mailing lists (e.g., `linux-mm`, `linux-kernel`, `qemu-devel`).

#### Example: Clone the `linux-mm` Mailing List Repository
```bash
# Clone the linux-mm mailing list repo to local directory "linux-mm-repo"
git clone https://erol.kernel.org/linux-mm/git/0 linux-mm-0-repo
```

Notes on EROL Repositories:

- Each EROL repository contains a core source file (typically named m) that stores the raw email data.
- Ensure the cloned repository has the m file (located in the root of the repo directory) before running the script.

### Step 2: Use m2a.sh to Process the Repository

After cloning the EROL repository, run m2a.sh to process the email data, specifying the path to the repo's m file.

```bash
./m2a.sh -o <output_directory> -e <end_date> -i <path_to_m_file>
```

e.g.

```
./m2a.sh -o ./qemu-devel-email -e 202101 -i ./linux-mm-0-repo/m
```