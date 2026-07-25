package media

import "testing"

func TestNaturalCompareHandlesCaseDigitsUnicodeAndLeadingZeros(t *testing.T) {
	tests := []struct{ left, right string }{
		{"alpha", "Bravo"},
		{"第2集", "第02集"},
		{"第02集", "第10集"},
		{"出生2", "出生10"},
	}
	for _, test := range tests {
		if NaturalCompare(test.left, test.right) >= 0 {
			t.Fatalf("NaturalCompare(%q, %q) should be ascending", test.left, test.right)
		}
		if NaturalCompare(test.right, test.left) <= 0 {
			t.Fatalf("NaturalCompare(%q, %q) should be descending", test.right, test.left)
		}
	}
}
