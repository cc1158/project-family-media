package metadata

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func photoCapturedAt(path string) (*time.Time, error) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".jpg", ".jpeg":
		return jpegCapturedAt(path)
	default:
		return nil, nil
	}
}

func jpegCapturedAt(path string) (*time.Time, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	header := make([]byte, 2)
	if _, err := io.ReadFull(file, header); err != nil {
		return nil, err
	}
	if header[0] != 0xff || header[1] != 0xd8 {
		return nil, nil
	}

	for {
		marker, payload, err := nextJPEGSegment(file)
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil, nil
			}
			return nil, err
		}
		if marker == 0xe1 && bytes.HasPrefix(payload, []byte("Exif\x00\x00")) {
			return exifCapturedAt(payload[6:])
		}
	}
}

func nextJPEGSegment(reader io.Reader) (byte, []byte, error) {
	var prefix [1]byte
	for {
		if _, err := io.ReadFull(reader, prefix[:]); err != nil {
			return 0, nil, err
		}
		if prefix[0] == 0xff {
			break
		}
	}

	var marker [1]byte
	for {
		if _, err := io.ReadFull(reader, marker[:]); err != nil {
			return 0, nil, err
		}
		if marker[0] != 0xff {
			break
		}
	}
	if marker[0] == 0xda || marker[0] == 0xd9 {
		return marker[0], nil, io.EOF
	}

	var lengthBytes [2]byte
	if _, err := io.ReadFull(reader, lengthBytes[:]); err != nil {
		return 0, nil, err
	}
	length := int(binary.BigEndian.Uint16(lengthBytes[:]))
	if length < 2 {
		return 0, nil, fmt.Errorf("invalid jpeg segment length %d", length)
	}
	payload := make([]byte, length-2)
	if _, err := io.ReadFull(reader, payload); err != nil {
		return 0, nil, err
	}
	return marker[0], payload, nil
}

func exifCapturedAt(tiff []byte) (*time.Time, error) {
	order, ok := tiffByteOrder(tiff)
	if !ok || len(tiff) < 8 || order.Uint16(tiff[2:4]) != 42 {
		return nil, nil
	}

	ifd0Offset := int(order.Uint32(tiff[4:8]))
	ifd0, ok := readIFD(tiff, ifd0Offset, order)
	if !ok {
		return nil, nil
	}

	exifOffset, ok := ifd0.uint32(0x8769)
	if !ok {
		if value, ok := ifd0.ascii(0x0132); ok {
			return parseExifDate(value, "")
		}
		return nil, nil
	}
	exifIFD, ok := readIFD(tiff, int(exifOffset), order)
	if !ok {
		return nil, nil
	}

	offset := ""
	if value, ok := exifIFD.ascii(0x9011); ok {
		offset = value
	}
	for _, tag := range []uint16{0x9003, 0x9004, 0x0132} {
		if value, ok := exifIFD.ascii(tag); ok {
			return parseExifDate(value, offset)
		}
	}
	return nil, nil
}

func tiffByteOrder(tiff []byte) (binary.ByteOrder, bool) {
	if len(tiff) < 2 {
		return binary.BigEndian, false
	}
	switch string(tiff[:2]) {
	case "II":
		return binary.LittleEndian, true
	case "MM":
		return binary.BigEndian, true
	default:
		return binary.BigEndian, false
	}
}

type ifd map[uint16]ifdEntry

type ifdEntry struct {
	fieldType uint16
	count     uint32
	value     uint32
	tiff      []byte
	order     binary.ByteOrder
}

func readIFD(tiff []byte, offset int, order binary.ByteOrder) (ifd, bool) {
	if offset < 0 || offset+2 > len(tiff) {
		return nil, false
	}
	count := int(order.Uint16(tiff[offset : offset+2]))
	entriesStart := offset + 2
	entriesEnd := entriesStart + count*12
	if entriesEnd > len(tiff) {
		return nil, false
	}

	result := make(ifd, count)
	for i := 0; i < count; i++ {
		raw := tiff[entriesStart+i*12 : entriesStart+(i+1)*12]
		tag := order.Uint16(raw[0:2])
		result[tag] = ifdEntry{
			fieldType: order.Uint16(raw[2:4]),
			count:     order.Uint32(raw[4:8]),
			value:     order.Uint32(raw[8:12]),
			tiff:      tiff,
			order:     order,
		}
	}
	return result, true
}

func (i ifd) uint32(tag uint16) (uint32, bool) {
	entry, ok := i[tag]
	if !ok {
		return 0, false
	}
	switch entry.fieldType {
	case 3:
		if entry.order == binary.LittleEndian {
			return uint32(uint16(entry.value)), true
		}
		return uint32(entry.value >> 16), true
	case 4:
		return entry.value, true
	default:
		return 0, false
	}
}

func (i ifd) ascii(tag uint16) (string, bool) {
	entry, ok := i[tag]
	if !ok || entry.fieldType != 2 || entry.count == 0 {
		return "", false
	}
	var raw []byte
	if entry.count <= 4 {
		value := make([]byte, 4)
		entry.order.PutUint32(value, entry.value)
		raw = value[:entry.count]
	} else {
		offset := int(entry.value)
		end := offset + int(entry.count)
		if offset < 0 || end > len(entry.tiff) {
			return "", false
		}
		raw = entry.tiff[offset:end]
	}
	return strings.TrimRight(string(raw), "\x00 "), true
}

func parseExifDate(value string, offset string) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" || strings.HasPrefix(value, "0000:00:00") {
		return nil, nil
	}
	if offset != "" {
		if parsed, err := time.Parse("2006:01:02 15:04:05 -07:00", value+" "+offset); err == nil {
			utc := parsed.UTC()
			return &utc, nil
		}
	}
	parsed, err := time.ParseInLocation("2006:01:02 15:04:05", value, time.Local)
	if err != nil {
		return nil, err
	}
	utc := parsed.UTC()
	return &utc, nil
}
