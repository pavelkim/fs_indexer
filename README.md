# Filesystem indexer

A workaround like the rkhunter.

```
sudo podman run \
  --rm \
  --interactive \
  --tty \
  --detach \
  --name fs_indexer \
  -e "SCAN_ROOT=/scan" \
  -e "HOSTNAME=${HOSTNAME}" \
  -v "/bin:/scan/bin:ro" \
  -v "/boot:/scan/boot:ro" \
  -v "/etc:/scan/etc:ro" \
  -v "/home:/scan/home:ro" \
  -v "/lib:/scan/lib:ro" \
  -v "/lib64:/scan/lib64:ro" \
  -v "/media:/scan/media:ro" \
  -v "/mnt:/scan/mnt:ro" \
  -v "/opt:/scan/opt:ro" \
  -v "/root:/scan/root:ro" \
  -v "/sbin:/scan/sbin:ro" \
  -v "/srv:/scan/srv:ro" \
  -v "/tmp:/scan/tmp:ro" \
  -v "/usr:/scan/usr:ro" \
  -v "/var:/scan/var:ro" \
  -v "/tmp/results:/results:Z" \
  --entrypoint "/bin/bash" \
  "ghcr.io/pavelkim/fs_indexer/fs_indexer:1.3.0"
```


