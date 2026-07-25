package metadata

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestJPEGCapturedAtReadsDateTimeOriginal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "photo.jpg")
	if err := os.WriteFile(path, jpegWithExif("2026:05:19 11:58:00", "+08:00"), 0o644); err != nil {
		t.Fatal(err)
	}

	capturedAt, err := jpegCapturedAt(path)
	if err != nil {
		t.Fatal(err)
	}
	if capturedAt == nil {
		t.Fatal("capturedAt is nil")
	}
	want := time.Date(2026, 5, 19, 3, 58, 0, 0, time.UTC)
	if !capturedAt.Equal(want) {
		t.Fatalf("capturedAt = %v, want %v", capturedAt, want)
	}
}

func TestJPEGCapturedAtIgnoresInvalidExifDate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "photo.jpg")
	if err := os.WriteFile(path, jpegWithExif("0000:00:00 00:00:00", ""), 0o644); err != nil {
		t.Fatal(err)
	}

	capturedAt, err := jpegCapturedAt(path)
	if err != nil {
		t.Fatal(err)
	}
	if capturedAt != nil {
		t.Fatalf("capturedAt = %v", capturedAt)
	}
}

func TestParseVideoTime(t *testing.T) {
	parsed, ok := parseVideoTime("2026-05-19T11:58:00.123456Z")
	if !ok {
		t.Fatal("parse failed")
	}
	want := time.Date(2026, 5, 19, 11, 58, 0, 123456000, time.UTC)
	if !parsed.Equal(want) {
		t.Fatalf("parsed = %v, want %v", parsed, want)
	}
}

func jpegWithExif(date string, offset string) []byte {
	tiff := tiffWithExif(date, offset)
	payload := append([]byte("Exif\x00\x00"), tiff...)
	var data bytes.Buffer
	data.Write([]byte{0xff, 0xd8})
	data.Write([]byte{0xff, 0xe1})
	_ = binary.Write(&data, binary.BigEndian, uint16(len(payload)+2))
	data.Write(payload)
	data.Write([]byte{0xff, 0xd9})
	return data.Bytes()
}

func tiffWithExif(date string, offset string) []byte {
	const ifd0Offset = 8
	const exifIFDOffset = 26
	const dateOffset = 72
	const offsetOffset = 92

	tiff := make([]byte, 128)
	copy(tiff[0:], []byte("II"))
	binary.LittleEndian.PutUint16(tiff[2:], 42)
	binary.LittleEndian.PutUint32(tiff[4:], ifd0Offset)

	binary.LittleEndian.PutUint16(tiff[ifd0Offset:], 1)
	writeIFDEntry(tiff[ifd0Offset+2:], 0x8769, 4, 1, exifIFDOffset)

	binary.LittleEndian.PutUint16(tiff[exifIFDOffset:], 2)
	writeIFDEntry(tiff[exifIFDOffset+2:], 0x9003, 2, uint32(len(date)+1), dateOffset)
	writeIFDEntry(tiff[exifIFDOffset+14:], 0x9011, 2, uint32(len(offset)+1), offsetOffset)
	copy(tiff[dateOffset:], append([]byte(date), 0))
	copy(tiff[offsetOffset:], append([]byte(offset), 0))
	return tiff
}

func writeIFDEntry(target []byte, tag uint16, fieldType uint16, count uint32, value uint32) {
	binary.LittleEndian.PutUint16(target[0:], tag)
	binary.LittleEndian.PutUint16(target[2:], fieldType)
	binary.LittleEndian.PutUint32(target[4:], count)
	binary.LittleEndian.PutUint32(target[8:], value)
}
