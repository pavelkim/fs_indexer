#!/bin/bash
# shellcheck disable=SC1091
# shellcheck disable=SC2181
# shellcheck disable=SC2015
#
# Lists all files on file system: counts md5sum and filesizes
#
# v1.0.0 2016-01-24 Initial version (Pavel Kim)
# v1.1.0 2018-02-21 Rearranged indexing stages (Pavel Kim)
# v1.2.0 2021-06-16 Refactoring (Pavel Kim)
# v1.3.0 2022-05-21 SQLite database support (Pavel Kim)

# HEADER:
# hostname                ${hostname}
# scan_uuid               ${scan_uuid}
# scan_time               ${now}
# last_access_time        %AY-%Am-%Ad %AT
# last_status_change_time %CY-%Cm-%Cd %CT
# last_modification_time  %TY-%Tm-%Td %TT
# depth_in_tree           %d
# basename                %f
# parent_directory        %h
# group_name              %g
# group_id                %G
# user_name               %u
# user_id                 %U
# inode_number            %i
# symlink_target          %l
# hardlinks_count         %n
# permissions_num         %#m
# name                    %p
# size_bytes              %s
# type                    %y
# selinux_context (excl.) %Z

[[ -f ".config" ]] && source .config || :

VERSION="1.3.0"
today=$( date +%Y%m%d )
now=$( date "+%F %T" )
hostname=$( hostname )
scan_uuid=$( uuidgen )
sqlite_database="database.sqlite3"

[[ -z "${GLOBAL_LOGLEVEL}" ]] && GLOBAL_LOGLEVEL="4"
[[ -z "${MUTEX_FILE}" ]] && MUTEX_FILE="$0.lock"

find_printf_format="${hostname}\t${scan_uuid}\t${now}\t%AY-%Am-%Ad %AT\t%CY-%Cm-%Cd %CT\t%TY-%Tm-%Td %TT\t%d\t%f\t%h\t%g\t%G\t%u\t%U\t%i\t%l\t%n\t%#m\t%p\t%s\t%y\n"
find_exceptions=(
    -not -path "/dev/*" 
    -not -path "/proc/*" 
    -not -path "/run/*" 
    -not -path "/sys/*" 
    -not -path "/cgroup/*"
)

output_dir="results/${today}"
if [[ ! -d "${output_dir}" ]]; then
    mkdir -p "${output_dir}"
fi

checksum_output_filename="${output_dir}/checksum_${hostname}_${today}.lst"
index_output_filename="${output_dir}/index_${hostname}_${today}.lst"
sizes_dir_output_filename="${output_dir}/sizes_dir_${hostname}_${today}.lst"
sizes_dir_file_output_filename="${output_dir}/sizes_dir_file_${hostname}_${today}.lst"


timestamp() {
    date "+%F %T"
}

error() {

        local msg
        local rc

        [[ -n "${1}" ]] && msg="ERROR: ${1}" || msg="ERROR!"
        [[ -n "${2}" ]] && rc="${2}" || rc=1

        echo "[$(timestamp)] ${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}: ${FUNCNAME[1]}: ${msg}" >&2
        exit "${rc}"
}

info() {

    local msg="$1"
    local self_level=3
    local self_level_name="info"

    if [[ "${self_level}" -le "${GLOBAL_LOGLEVEL}" ]]; then 
        echo "[$(timestamp)] [${self_level_name}] [${FUNCNAME[1]}] ${msg}" >&2
        return 0
    fi
}



create_mutex() {
    
    local current_mutex_content

    info "Creating mutex."

    echo "$$" > "${MUTEX_FILE}"

    if [[ -f "${MUTEX_FILE}" ]]; then
        current_mutex_content=$( cat "${MUTEX_FILE}" )
        [[ "$$" == "${current_mutex_content}" ]] || error "Can't create mutex. My PID=$$ but in file is ${current_mutex_content}."
    else
        error "Mutex hasn't been created at all: ${MUTEX_FILE}"
    fi

    info "Mutex created. PID=${current_mutex_content}"

    return 0
}

remove_mutex() {

    info "Removing mutex."

    [[ -f "${MUTEX_FILE}" ]] && rm -f "${MUTEX_FILE}"
}

mutex_start() {

    local previous_process_pid

    if [[ -f "${MUTEX_FILE}" ]]; then
        info "Mutex found."

        previous_process_pid=$(cat "${MUTEX_FILE}")
        
        if ps -p "${previous_process_pid}" > /dev/null 2>&1; then
            info "Previous process with PID ${previous_process_pid} found."
            info "Can't continue."
            exit 0
        else
            info "Process with PID ${previous_process_pid} not found."
            info "Grabbing lock and continue."

            create_mutex
        fi
    else
        info "No mutex found. Creating one."
        create_mutex
    fi
    
    return 0
}

mutex_stop() {
    remove_mutex
}


mutex_start

info "Starting filesystem scan v${VERSION} (${scan_uuid})"

info "Starting dir size indexing"
info "Indexing output file: ${sizes_dir_output_filename}"
du --exclude /proc --exclude /dev --exclude /sys --exclude /run -S / > "${sizes_dir_output_filename}"
[[ "$?" != "0" ]] && error "Error while indexind dirs."
info "Finished dir size indexing"

info "Starting dir and file size indexing"
info "Indexing output file: ${sizes_dir_file_output_filename}"
du --exclude /proc --exclude /dev --exclude /sys --exclude /run -a / > "${sizes_dir_file_output_filename}"
[[ "$?" != "0" ]] && error "Error while indexing dirs and files."
info "Finished dir and file size indexing"

info "Starting file size indexing"
info "Indexing output file: ${index_output_filename}"
find / "${find_exceptions[@]}" -printf "${find_printf_format}" > "${index_output_filename}"
[[ "$?" != "0" ]] && error "Error while finding files."
info "Finished file size indexing"

info "Starting md5sum indexing"
info "Indexing output file: ${checksum_output_filename}"
find / "${find_exceptions[@]}" -type f -exec md5sum {} \; > "${checksum_output_filename}"
[[ "$?" != "0" ]] && error "Error while finding files."
info "Finished md5sum indexing"

sed -e "s/^/${hostname}\t${scan_uuid}\t${now}\tmd5\t/" -e "s/ \+ /\t/g" "${checksum_output_filename}" > "${checksum_output_filename}.tsv"


info "Loading collected data into SQLite database"

info "Initialising schema for fs_index table"
sqlite3 "${sqlite_database}" << EOQ
create table if not exists fs_index (
  hostname                   TEXT,
  scan_uuid                  TEXT,
  scan_time                  DATETIME,
  last_access_time           DATETIME,
  last_status_change_time    DATETIME,
  last_modification_time     DATETIME,
  depth_in_tree              INTEGER,
  basename                   TEXT,
  parent_directory           TEXT,
  group_name                 TEXT,
  group_id                   INTEGER,
  user_name                  TEXT,
  user_id                    INTEGER,
  inode_number               INTEGER,
  symlink_target             TEXT,
  hardlinks_count            INTEGER,
  permissions_num            TEXT,
  name                       TEXT,
  size_bytes                 INTEGER,
  type                       TEXT
);

CREATE INDEX idx_fs_index_name on fs_index (name);
CREATE INDEX idx_fs_index_scan_uuid on fs_index (scan_uuid);
CREATE INDEX idx_fs_index_last_modification_time on fs_index (last_modification_time);
EOQ


info "Initialising schema for fs_checksum table"
sqlite3 "${sqlite_database}" << EOQ
create table if not exists fs_checksum (
  hostname                  TEXT,
  scan_uuid                 TEXT,
  scan_time                 DATETIME,
  checksum_type             TEXT,
  checksum                  TEXT,
  name                      TEXT
);

CREATE INDEX idx_fs_checksum_name on fs_checksum (name);
CREATE INDEX idx_fs_checksum_scan_uuid on fs_checksum (scan_uuid);
CREATE INDEX idx_fs_checksum_checksum on fs_checksum (checksum);
CREATE INDEX idx_fs_checksum_checksum_name on fs_checksum (checksum, name);
EOQ


info "Initialising schema for fs_scan_history table"
sqlite3 "${sqlite_database}" << EOQ
create table if not exists fs_scan_history (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  scan_uuid              TEXT,
  scan_time              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  VERSION                TEXT,
  hostname               TEXT
);
EOQ


info "Registering scan in the scan history"
sqlite3 "${sqlite_database}" << EOQ
insert into fs_scan_history (scan_uuid, hostname, VERSION) values ("${scan_uuid}", "${hostname}", "${VERSION}");
EOQ


info "Importing collected data into the database"
sqlite3 "${sqlite_database}" << EOQ
.mode csv
.separator \t
.import ${index_output_filename} fs_index
.import ${checksum_output_filename}.tsv fs_checksum
EOQ


info "Fixing up data types in the database"
sqlite3 "${sqlite_database}" << EOQ
.mode csv
.header off
update fs_checksum set scan_time = DATETIME(scan_time);
update fs_index set scan_time = DATETIME(scan_time), 
 last_access_time = DATETIME(last_access_time), 
 last_status_change_time = DATETIME(last_status_change_time), 
 last_modification_time = DATETIME(last_modification_time);
EOQ


info "GZipping results"
[[ -f "${checksum_output_filename}.gz" ]] && rm -f "${checksum_output_filename}.gz"
gzip "${checksum_output_filename}"
[[ "$?" != "0" ]] && error "Error while gzipping index."

[[ -f "${index_output_filename}.gz" ]] && rm -f "${index_output_filename}.gz"
gzip "${index_output_filename}"
[[ "$?" != "0" ]] && error "Error while gzipping sizes."

[[ -f "${sizes_dir_output_filename}.gz" ]] && rm -f "${sizes_dir_output_filename}.gz"
gzip "${sizes_dir_output_filename}"
[[ "$?" != "0" ]] && error "Error while gzipping sizes."

[[ -f "${sizes_dir_file_output_filename}.gz" ]] && rm -f "${sizes_dir_file_output_filename}.gz"
gzip "${sizes_dir_file_output_filename}"
[[ "$?" != "0" ]] && error "Error while gzipping sizes."


info "Filesystem index: '${index_output_filename}.gz'"
info "Checksum index: '${checksum_output_filename}.gz'"
info "Full sizes index: '${sizes_dir_file_output_filename}.gz'"
info "Directory sizes index: '${sizes_dir_output_filename}.gz'"

mutex_stop
