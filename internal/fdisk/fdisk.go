package fdisk

// BlockDevice represents a Partition or a Hard-Disk
type BlockDevice interface {
	GetDeviceName() string
	GetDeviceFileName() string
}

// Partition represents a Partition on a Hard-Disk
type Partition interface {
	BlockDevice
}

// Disk represents a Hard-Disk
type Disk interface {
	BlockDevice
	IsRemovable() bool
	GetPartitions() ([]Partition, error)
}
