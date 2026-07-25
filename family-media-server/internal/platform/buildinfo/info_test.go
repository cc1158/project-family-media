package buildinfo

import "testing"

func TestCurrentReportsDevelopmentDefaults(t *testing.T) {
	t.Setenv("FAMILY_MEDIA_BINARY_SOURCE", "")
	info := Current()
	if info.Version == "" || info.Commit == "" || info.BuiltAt == "" {
		t.Fatalf("build info contains empty fields: %#v", info)
	}
	if info.Source != "development" {
		t.Fatalf("source = %q", info.Source)
	}
}

func TestCurrentAcceptsKnownRuntimeSources(t *testing.T) {
	for _, source := range []string{"external", "bundled"} {
		t.Run(source, func(t *testing.T) {
			t.Setenv("FAMILY_MEDIA_BINARY_SOURCE", source)
			if current := Current().Source; current != source {
				t.Fatalf("source = %q, want %q", current, source)
			}
		})
	}
}

func TestCurrentRejectsUnknownRuntimeSource(t *testing.T) {
	t.Setenv("FAMILY_MEDIA_BINARY_SOURCE", "unexpected")
	if source := Current().Source; source != "development" {
		t.Fatalf("source = %q", source)
	}
}
