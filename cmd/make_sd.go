package main

import (
	"fmt"

	"github.com/dueckminor/mypi-setup-alpine/internal/fdisk"
)

func main() {
	disks, err := fdisk.GetDisks()
	if err != nil {
		panic(err)
	}

	for _, disk := range disks {
		if !disk.IsRemovable() {
			continue
		}
		fmt.Println(disk.GetDeviceName())
		partitions, _ := disk.GetPartitions()
		for _, partition := range partitions {
			fmt.Println("  " + partition.GetDeviceName())
		}
	}
}
