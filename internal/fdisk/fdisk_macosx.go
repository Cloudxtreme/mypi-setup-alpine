package fdisk

import (
	"bytes"
	"os/exec"
	"strings"

	"howett.net/plist"
)

type PList struct {
	content map[string]interface{}
}

func (obj PList) followPath(path ...interface{}) (interface{}, error) {
	var where interface{}
	where = obj.content
	for _, pathElement := range path {
		if name, ok := pathElement.(string); ok {
			if dict, ok := where.(map[string]interface{}); ok {
				where, ok = dict[name]
				if !ok {
					return nil, nil
				}
			}
		}
		if index, ok := pathElement.(int); ok {
			if arr, ok := where.([]interface{}); ok {
				where = arr[index]
				if !ok {
					return nil, nil
				}
			}
		}
	}
	return where, nil
}

func (obj PList) getSliceOfStrings(path ...interface{}) (result []string, err error) {
	where, err := obj.followPath(path...)
	if arr, ok := where.([]interface{}); ok {
		result = make([]string, len(arr))
		for index, item := range arr {
			if name, ok := item.(string); ok {
				result[index] = name
			} else {
				return nil, nil
			}
		}
		return result, nil
	}
	return nil, nil
}

func (obj PList) getString(path ...interface{}) (result string, err error) {
	where, err := obj.followPath(path...)
	if result, ok := where.(string); ok {
		return result, nil
	}
	return "", nil
}

func (obj PList) getInt(path ...interface{}) (result int64, err error) {
	where, err := obj.followPath(path...)
	if result, ok := where.(int64); ok {
		return result, nil
	}
	return 0, nil
}

func (obj PList) getBool(path ...interface{}) (result bool, err error) {
	where, err := obj.followPath(path...)
	if result, ok := where.(bool); ok {
		return result, nil
	}
	return false, nil
}

func callDiskutil(args ...string) (result PList, err error) {
	result = PList{}
	out, err := exec.Command("diskutil", args...).Output()
	if err != nil {
		return result, err
	}
	decoder := plist.NewDecoder(bytes.NewReader(out))
	err = decoder.Decode(&result.content)
	if err != nil {
		return result, err
	}
	return result, nil
}

type macosBlockDevice struct {
	deviceName     string
	deviceFileName string
	info           PList
}

func (dev macosBlockDevice) GetDeviceName() string {
	return dev.deviceName
}
func (dev macosBlockDevice) GetDeviceFileName() string {
	return dev.deviceFileName
}
func (dev macosBlockDevice) GetSize() int64 {
	s, _ := dev.info.getInt("TotalSize")
	return s
}

type macosPartition struct {
	macosBlockDevice
}

func macosNewPartition(deviceName string) (result macosPartition, err error) {
	result.info, err = callDiskutil("info", "-plist", deviceName)
	if err != nil {
		return macosPartition{}, nil
	}
	result.deviceName = deviceName
	return result, err
}

type macosDisk struct {
	macosBlockDevice
	partitionNames []string
	partitions     []Partition
}

func newDiskMacos(deviceName string, partitions []string) (result macosDisk, err error) {
	result.info, err = callDiskutil("info", "-plist", deviceName)
	if err != nil {
		return macosDisk{}, nil
	}
	result.deviceName = deviceName
	result.partitionNames = partitions
	return result, err
}

func (dev macosDisk) IsRemovable() bool {
	removeable, _ := dev.info.getBool("Removable")
	return removeable
}

func (dev macosDisk) GetPartitions() ([]Partition, error) {
	if len(dev.partitionNames) > len(dev.partitions) {
		partitions := make([]Partition, len(dev.partitionNames))
		for index, name := range dev.partitionNames {
			partition, err := macosNewPartition(name)
			if err != nil {
				return nil, err
			}
			partitions[index] = partition
		}
		dev.partitions = partitions
	}
	return dev.partitions, nil
}

func getPartitionNames(diskDevice string, disksAndPartitions []string) (result []string) {
	for _, diskOrPartition := range disksAndPartitions {
		if (len(diskOrPartition) > len(diskDevice)) &&
			strings.HasPrefix(diskOrPartition, diskDevice) {
			result = append(result, diskOrPartition)
		}
	}
	return result
}

// GetRemovableDisks return all removable disks
func GetDisks() ([]Disk, error) {
	info, err := callDiskutil("list", "-plist")
	if err != nil {
		return nil, err
	}

	diskNames, err := info.getSliceOfStrings("WholeDisks")
	if err != nil {
		return nil, err
	}

	disksAndPartitions, err := info.getSliceOfStrings("AllDisks")

	result := make([]Disk, 0)

	for _, diskName := range diskNames {
		disk, err := newDiskMacos(diskName,
			getPartitionNames(diskName, disksAndPartitions))
		if err != nil {
			continue
		}
		result = append(result, disk)
	}

	return result, nil
}
