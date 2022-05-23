#!/bin/bash
# shellcheck disable=SC1091,SC2181,SC2015
#
# Lists all files on file system: counts md5sum and filesizes
#


[[ -f ".config" ]] && source .config || :

VERSION="0.0.0"
today=$( date +%Y%m%d )
hostname=$( hostname )
scan_uuid=$( uuidgen )

[[ -z "${WORKDIR}" ]] && WORKDIR="$(pwd)"

output_dir="${WORKDIR}/results/${today}"
if [[ ! -d "${output_dir}" ]]; then
    mkdir -p "${output_dir}"
fi


[[ -z "${GLOBAL_LOGLEVEL}" ]] && GLOBAL_LOGLEVEL="4"
[[ -z "${LOGFILE}" ]] && LOGFILE="${output_dir}/${hostname}.log"
[[ -z "${MUTEX_FILE}" ]] && MUTEX_FILE="${WORKDIR}/${0}.lock"
[[ -z "${SQLITE_DATABASE}" ]] && SQLITE_DATABASE="${WORKDIR}/database.sqlite3"

# TODO: Check if SCAN_ROOT has a trailing /
[[ -z "${SCAN_ROOT}" ]] && SCAN_ROOT="/"


# TODO: Manage find_exceptions from config
find_printf_format="${hostname}\t${scan_uuid}\t%AY-%Am-%Ad %AT\t%CY-%Cm-%Cd %CT\t%TY-%Tm-%Td %TT\t%d\t%f\t%h\t%g\t%G\t%u\t%U\t%i\t%l\t%n\t%#m\t%p\t%s\t%y\n"
find_exceptions=(
    -not -path "/dev/*" 
    -not -path "/proc/*" 
    -not -path "/run/*" 
    -not -path "/sys/*" 
    -not -path "/cgroup/*"
    -not -path "/swap"
)

# TODO: Allow user to run more granular scans (more often than once per day)
checksum_output_filename="${output_dir}/checksum_${hostname}_${today}.lst"
checksum_output_logfile="${output_dir}/checksum_${hostname}_${today}.log"
index_output_filename="${output_dir}/index_${hostname}_${today}.lst"
index_output_logfile="${output_dir}/index_${hostname}_${today}.log"

# TODO: Check for global variables to be defined in the functions

timestamp() {
    date "+%F %T"
}

error() {

        local msg
        local rc

        [[ -n "${1}" ]] && msg="ERROR: ${1}" || msg="ERROR!"
        [[ -n "${2}" ]] && rc="${2}" || rc=1

        echo "[$(timestamp)] ${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}: ${FUNCNAME[1]}: ${msg}" >&2
        echo "[$(timestamp)] ${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}: ${FUNCNAME[1]}: ${msg}" >> "${LOGFILE}"
        exit "${rc}"
}

warning() {

    local msg
    local self_level
    local self_level_name

    msg="${1}"
    self_level=2
    self_level_name="warning"

    if [[ "${self_level}" -le "${GLOBAL_LOGLEVEL}" ]]; then 
        echo "[$(timestamp)] [${self_level_name}] [${FUNCNAME[1]}] ${msg}" >&2
        echo "[$(timestamp)] [${self_level_name}] [${FUNCNAME[1]}] ${msg}" >> "${LOGFILE}"
        return 0
    fi
}

info() {

    local msg
    local self_level
    local self_level_name

    msg="${1}"
    self_level=3
    self_level_name="info"

    if [[ "${self_level}" -le "${GLOBAL_LOGLEVEL}" ]]; then 
        echo "[$(timestamp)] [${self_level_name}] [${FUNCNAME[1]}] ${msg}" >&2
        echo "[$(timestamp)] [${self_level_name}] [${FUNCNAME[1]}] ${msg}" >> "${LOGFILE}"
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

index_files() {

    info "Starting file indexing"
    info "Indexing output file: ${index_output_filename}"
    
    find "${SCAN_ROOT}" "${find_exceptions[@]}" -printf "${find_printf_format}" > "${index_output_filename}" 2>"${checksum_output_logfile}"
    [[ "$?" != "0" ]] && warning "There were errors during building the index. Look into the logfile: '${checksum_output_logfile}'"
    info "Finished file indexing"

}

index_checksums() {

    info "Starting checksum indexing"
    info "Indexing output file: ${checksum_output_filename}"

    find "${SCAN_ROOT}" "${find_exceptions[@]}" -type f -exec md5sum {} \; > "${checksum_output_filename}" 2>"${index_output_logfile}"
    [[ "$?" != "0" ]] && warning "There were errors during building checksums. Look into the logfile: '${index_output_logfile}'"
    info "Finished checksum indexing"

    info "Supplying extra information"
    sed -e "s/^/${hostname}\t${scan_uuid}\tmd5\t/" -e "s/ \+ /\t/g" "${checksum_output_filename}" > "${checksum_output_filename}.tsv"

}

init_db() {

    info "Initialising schema for fs_index table"
    sqlite3 "${SQLITE_DATABASE}" << EOQ
CREATE TABLE IF NOT EXISTS fs_index (
     hostname                TEXT,
     scan_uuid               TEXT,
     last_access_time        DATETIME,
     last_status_change_time DATETIME,
     last_modification_time  DATETIME,
     depth_in_tree           INTEGER,
     basename                TEXT,
     parent_directory        TEXT,
     group_name              TEXT,
     group_id                INTEGER,
     user_name               TEXT,
     user_id                 INTEGER,
     inode_number            INTEGER,
     symlink_target          TEXT,
     hardlinks_count         INTEGER,
     permissions_num         TEXT,
     name                    TEXT,
     size_bytes              INTEGER,
     type                    TEXT
);

CREATE INDEX IF NOT EXISTS idx_fs_index_scan_uuid ON fs_index (scan_uuid);
-- CREATE INDEX IF NOT EXISTS idx_fs_index_name ON fs_index (name);
-- CREATE INDEX IF NOT EXISTS idx_fs_index_last_modification_time ON fs_index (last_modification_time);
EOQ

    info "Initialising schema for fs_checksum table"
    sqlite3 "${SQLITE_DATABASE}" << EOQ
CREATE TABLE IF NOT EXISTS fs_checksum (
     hostname      TEXT,
     scan_uuid     TEXT,
     checksum_type TEXT,
     checksum      TEXT,
     name          TEXT
);

CREATE INDEX IF NOT EXISTS idx_fs_checksum_scan_uuid_name ON fs_checksum (scan_uuid, name);
CREATE INDEX IF NOT EXISTS idx_fs_checksum_checksum_name ON fs_checksum (checksum, name);
CREATE INDEX IF NOT EXISTS idx_fs_checksum_name ON fs_checksum (name);
-- CREATE INDEX IF NOT EXISTS idx_fs_checksum_scan_uuid ON fs_checksum (scan_uuid);
-- CREATE INDEX IF NOT EXISTS idx_fs_checksum_checksum ON fs_checksum (checksum);
EOQ


    info "Initialising schema for fs_scan_history table"
    sqlite3 "${SQLITE_DATABASE}" << EOQ
CREATE TABLE IF NOT EXISTS fs_scan_history (
     id INTEGER PRIMARY KEY autoincrement,
     scan_uuid        text,
     scan_time_start  DATETIME,
     scan_time_finish DATETIME,
     version          text,
     hostname         text
);
EOQ
}

import_results_to_db() {

    info "Importing collected data into the database"
    sqlite3 "${SQLITE_DATABASE}" << EOQ
.mode csv
.separator \t
.import ${index_output_filename} fs_index
.import ${checksum_output_filename}.tsv fs_checksum
EOQ


    info "Fixing up data types in the database"
    sqlite3 "${SQLITE_DATABASE}" << EOQ
.mode csv
.header off

UPDATE fs_index
SET last_access_time = DATETIME(last_access_time),
    last_status_change_time = DATETIME(last_status_change_time),
    last_modification_time = DATETIME(last_modification_time)
WHERE scan_uuid = '${scan_uuid}';
EOQ

}

create_views_in_db() {

    info "Creating views in the database"

    sqlite3 "${SQLITE_DATABASE}" << EOQ
DROP VIEW IF EXISTS fs_index_last;
CREATE view fs_index_last
AS
  SELECT *
  FROM   fs_index
  WHERE  fs_index.scan_uuid = '${scan_uuid}';

DROP VIEW IF EXISTS fs_checksum_last;
CREATE view fs_checksum_last
AS
  SELECT *
  FROM   fs_checksum
  WHERE  fs_checksum.scan_uuid = '${scan_uuid}';

DROP VIEW IF EXISTS fs_full_report_last;
CREATE view fs_full_report_last
AS
  SELECT *
  FROM fs_index
  JOIN fs_checksum
  ON fs_index.name = fs_checksum.name
  WHERE  fs_index.scan_uuid = '${scan_uuid}';


DROP VIEW IF EXISTS fs_scan_history_extended;
CREATE view fs_scan_history_extended
AS
  SELECT id,
    scan_uuid,
    scan_time_start,
    scan_time_finish,
    version,
    hostname,
    CAST(
        (JulianDay(scan_time_finish) - JulianDay(scan_time_start)) * 24 * 60 * 60
    AS Integer) as duration_seconds,
    CAST(
        (JulianDay(scan_time_finish) - JulianDay(scan_time_start)) * 24 * 60
    AS Integer) as duration_minutes,
    CAST(
        (JulianDay(scan_time_finish) - JulianDay(scan_time_start)) * 24
    AS Integer) as duration_hours
  FROM fs_scan_history;
EOQ


    if [[ -n "${previous_scan_uuid}" ]]; then
        sqlite3 "${SQLITE_DATABASE}" << EOQ
DROP VIEW IF EXISTS fs_checksum_diff_last;
CREATE view fs_checksum_diff_last
AS
  SELECT name
  FROM   (SELECT scan_uuid,
                 name,
                 checksum,
                 COUNT(name) AS count
          FROM fs_checksum
          WHERE scan_uuid IN (
            '${previous_scan_uuid}',
            '${scan_uuid}'
          )
          GROUP  BY checksum, name
          ORDER  BY count, name ASC)
  WHERE  count = 1
  GROUP  BY name;
EOQ

    else
        warning "First scan. Not creating comparison view."
    fi

}

compress_results() {

    info "gzipping results"
    [[ -f "${index_output_filename}.gz" ]] && rm -f "${index_output_filename}.gz"
    gzip "${index_output_filename}"
    [[ "$?" != "0" ]] && error "Error while gzipping index: ${index_output_filename}"

    [[ -f "${checksum_output_filename}.gz" ]] && rm -f "${checksum_output_filename}.gz"
    gzip "${checksum_output_filename}"
    [[ "$?" != "0" ]] && error "Error while gzipping checksum index: ${checksum_output_filename}"

    [[ -f "${checksum_output_filename}.tsv.gz" ]] && rm -f "${checksum_output_filename}.tsv.gz"
    gzip "${checksum_output_filename}.tsv"
    [[ "$?" != "0" ]] && error "Error while gzipping checksum index: ${checksum_output_filename}.tsv"

}

get_previous_scan_uuid() {

    info "Get previous scan UUID from the database"

    previous_scan_uuid_filename=$( mktemp )
    info "Created a temporary file: '${previous_scan_uuid_filename}'"

    sqlite3 "${SQLITE_DATABASE}" << EOQ > "${previous_scan_uuid_filename}"
SELECT scan_uuid
FROM fs_scan_history
ORDER BY id DESC
LIMIT 1;  
EOQ

    previous_scan_uuid=$(cat "${previous_scan_uuid_filename}")
    [[ -z "${previous_scan_uuid}" ]] && previous_scan_uuid="${scan_uuid}"
    info "Previous scan UUID: ${previous_scan_uuid}"

}

register_scan_in_db() {

    info "Registering scan in the scan history"

    sqlite3 "${SQLITE_DATABASE}" << EOQ
INSERT INTO fs_scan_history (
  scan_uuid,
  hostname,
  version,
  scan_time_start,
  scan_time_finish
) VALUES (
  "${scan_uuid}",
  "${hostname}",
  "${VERSION}",
  DATETIME("${scan_time_start}"),
  DATETIME("${scan_time_finish}")
);
EOQ

}

main() {
    mutex_start

    scan_time_start=$( date "+%F %T" )

    info "Starting filesystem scan v${VERSION} (${scan_uuid})"
    info "Scan root: '${SCAN_ROOT}'"

    index_files
    index_checksums

    scan_time_finish=$( date "+%F %T" )

    info "Scan start time: ${scan_time_start}"
    info "Scan finish time: ${scan_time_finish}"

    info "Loading collected data into SQLite database"

    init_db

    get_previous_scan_uuid

    register_scan_in_db

    import_results_to_db

    create_views_in_db

    compress_results

    info "Filesystem index: '${index_output_filename}.gz'"
    info "Checksum index: '${checksum_output_filename}.gz'"
    info "Database: '${SQLITE_DATABASE}'"

    mutex_stop
}

main
