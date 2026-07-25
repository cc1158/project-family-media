package media

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
)

var errTrailingCursorData = errors.New("cursor contains trailing data")

func encodeOpaqueCursor(value any) string {
	data, _ := json.Marshal(value)
	return base64.RawURLEncoding.EncodeToString(data)
}

func decodeOpaqueCursor(value string, destination any) error {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return errTrailingCursorData
		}
		return err
	}
	return nil
}
