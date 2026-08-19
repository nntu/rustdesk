package api

import (
	"testing"

	"rustdesk-api/global"
	"rustdesk-api/lib/cache"
)

func TestAuditNonceCacheRoundTrip(t *testing.T) {
	global.Cache = cache.NewMemoryCache(0)

	if _, ok := loadAuditNonceResult("missing"); ok {
		t.Fatal("expected cache miss")
	}

	storeAuditNonceResult("nonce-1", "guid-1")

	got, ok := loadAuditNonceResult("nonce-1")
	if !ok {
		t.Fatal("expected cache hit")
	}
	if got != "guid-1" {
		t.Fatalf("expected guid-1, got %q", got)
	}
}

func TestAuditNonceCacheEmptyResultStillHits(t *testing.T) {
	global.Cache = cache.NewMemoryCache(0)

	storeAuditNonceResult("nonce-2", "")

	got, ok := loadAuditNonceResult("nonce-2")
	if !ok {
		t.Fatal("expected cache hit for empty result")
	}
	if got != "" {
		t.Fatalf("expected empty result, got %q", got)
	}
}
