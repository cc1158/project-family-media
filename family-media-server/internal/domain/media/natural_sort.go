package media

import "strings"

// NaturalCompare compares names case-insensitively and treats ASCII digit
// runs numerically, so names such as "第2集" sort before "第10集".
func NaturalCompare(left, right string) int {
	l, r := []rune(strings.ToLower(left)), []rune(strings.ToLower(right))
	for li, ri := 0, 0; li < len(l) && ri < len(r); {
		if isASCIIDigit(l[li]) && isASCIIDigit(r[ri]) {
			lend, rend := digitRunEnd(l, li), digitRunEnd(r, ri)
			comparison := compareDigitRuns(l[li:lend], r[ri:rend])
			if comparison != 0 {
				return comparison
			}
			li, ri = lend, rend
			continue
		}
		if l[li] != r[ri] {
			if l[li] < r[ri] {
				return -1
			}
			return 1
		}
		li, ri = li+1, ri+1
	}
	if len(l) < len(r) {
		return -1
	}
	if len(l) > len(r) {
		return 1
	}
	return strings.Compare(left, right)
}

func isASCIIDigit(value rune) bool { return value >= '0' && value <= '9' }

func digitRunEnd(value []rune, start int) int {
	end := start
	for end < len(value) && isASCIIDigit(value[end]) {
		end++
	}
	return end
}

func compareDigitRuns(left, right []rune) int {
	leftValue := strings.TrimLeft(string(left), "0")
	rightValue := strings.TrimLeft(string(right), "0")
	if leftValue == "" {
		leftValue = "0"
	}
	if rightValue == "" {
		rightValue = "0"
	}
	if len(leftValue) != len(rightValue) {
		if len(leftValue) < len(rightValue) {
			return -1
		}
		return 1
	}
	if comparison := strings.Compare(leftValue, rightValue); comparison != 0 {
		return comparison
	}
	return len(left) - len(right)
}
