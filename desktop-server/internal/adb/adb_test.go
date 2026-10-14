package adb

import (
	"reflect"
	"testing"
)

func TestParseDevices(t *testing.T) {
	out := "List of devices attached\nR58M123ABC\tdevice\nemulator-5554\tunauthorized\nZY22\toffline\n\n"
	if got := parseDevices(out); !reflect.DeepEqual(got, []string{"R58M123ABC"}) {
		t.Fatalf("got %v", got)
	}
}
