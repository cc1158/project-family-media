package media

import (
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"path"
	"strings"

	domainmedia "family-media-server/internal/domain/media"
)

const (
	defaultBrowseLimit        = 50
	maxBrowseLimit            = 200
	folderContainerPrefix     = "family-folder:path:"
	unclassifiedContainerID   = "family-folder:unclassified"
	unclassifiedContainerName = "未分类"
)

type browseCursor struct {
	FolderOffset int                  `json:"folderOffset,omitempty"`
	Media        *domainmedia.PageKey `json:"media,omitempty"`
	Scope        string               `json:"scope"`
}

func encodeFolderContainerID(folderPath string) string {
	return folderContainerPrefix + base64.RawURLEncoding.EncodeToString([]byte(folderPath))
}

func decodeContainerID(containerID string) (string, bool, error) {
	if containerID == "" {
		return "", false, nil
	}
	if containerID == unclassifiedContainerID {
		return "", true, nil
	}
	if !strings.HasPrefix(containerID, folderContainerPrefix) {
		return "", false, domainmedia.ErrInvalidContainer
	}
	encoded := strings.TrimPrefix(containerID, folderContainerPrefix)
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return "", false, domainmedia.ErrInvalidContainer
	}
	folderPath := string(decoded)
	if folderPath == "" || path.IsAbs(folderPath) || path.Clean(folderPath) != folderPath ||
		folderPath == ".." || strings.HasPrefix(folderPath, "../") {
		return "", false, domainmedia.ErrInvalidContainer
	}
	return folderPath, false, nil
}

func normalizeBrowseLimit(limit int) int {
	if limit <= 0 {
		return defaultBrowseLimit
	}
	if limit > maxBrowseLimit {
		return maxBrowseLimit
	}
	return limit
}

func browseScope(kind domainmedia.Kind, containerID string, sortMode domainmedia.Sort) string {
	sum := sha1.Sum([]byte(string(kind) + ":" + containerID + ":" + string(sortMode)))
	return hex.EncodeToString(sum[:])
}

func encodeBrowseCursor(cursor browseCursor) string {
	return encodeOpaqueCursor(cursor)
}

func decodeBrowseCursor(cursor string, scope string) (browseCursor, error) {
	if cursor == "" {
		return browseCursor{Scope: scope}, nil
	}
	var decoded browseCursor
	if err := decodeOpaqueCursor(cursor, &decoded); err != nil || decoded.FolderOffset < 0 || decoded.Scope != scope {
		return browseCursor{}, domainmedia.ErrInvalidCursor
	}
	return decoded, nil
}
