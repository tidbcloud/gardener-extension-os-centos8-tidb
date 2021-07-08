#!/bin/sh

if [ ! -e "/dev/nvme0n1" ] ; then
  exit 0
fi

# Aws volume path /dev/nvme0n1, /dev/nvme1n1
devs=$(ls -lh /dev/nvme*n1 | awk '{print $10}')
gcpDevs=$(ls -lh /dev/nvme0n* | awk '{print $10}')

if [ $(echo "$devs" | wc -l) -lt $(echo "$gcpDevs" | wc -l) ] ; then
  devs=$gcpDevs
fi

# Don't combine if there is 1 disk.
if [ "$(echo "$devs" | wc -l)" -eq 1 ] ; then
  if ls /dev/nvme0n1p* > /dev/null 2>&1; then
    echo "disk /dev/nvme0n1 already parted, skipping"
  else
    echo "disk /dev/nvme0n1 is not parted"
    if ! blkid /dev/nvme0n1 > /dev/null; then
      echo none > /sys/block/nvme0n1/queue/scheduler
      mkfs -t ext4 /dev/nvme0n1
      DISK_UUID=$(blkid -s UUID -o value /dev/nvme0n1)
      mkdir -p /mnt/local-ssd/$DISK_UUID
      echo UUID=`blkid -s UUID -o value /dev/nvme0n1` /mnt/local-ssd/$DISK_UUID ext4 defaults 0 2 | tee -a /etc/fstab
    fi
  fi
  exit 0
fi

for path in $devs; do
    echo ${path#"/dev/"}
    echo none > /sys/block/${path#"/dev/"}/queue/scheduler
done

raid_dev=/dev/md0
if [ -e $raid_dev ] ; then
  exit 0
fi

echo y | /sbin/mdadm --create $raid_dev --level=0 --raid-devices=$(echo "$devs" | wc -l) $devs --force
sudo mkfs.ext4 -F $raid_dev
new_dev=$raid_dev
if ! uuid=$(blkid -s UUID -o value $new_dev) ; then
  mkfs.ext4 $new_dev
  uuid=$(blkid -s UUID -o value $new_dev)
fi

mnt_dir="/mnt/local-ssd/$uuid"
mkdir -p "$mnt_dir"

if ! grep "$uuid" /etc/fstab ; then
  echo "UUID=$uuid $mnt_dir ext4 $mnt_opts" >> /etc/fstab
fi
mount -U "$uuid" -t ext4 --target "$mnt_dir" --options "$mnt_opts"
chmod a+w "$mnt_dir"