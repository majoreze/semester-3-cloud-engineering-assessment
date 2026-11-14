package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfigFromEnvironment(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("MONGO_URI", "mongodb://localhost:27017")
	t.Setenv("DB_NAME", "test_db")
	t.Setenv("JWT_SECRET_KEY", "test-secret-key")
	t.Setenv("JWT_EXPIRATION_HOURS", "48")
	t.Setenv("ENABLE_CACHE", "true")
	t.Setenv("REDIS_ADDR", "localhost:6379")
	t.Setenv("REDIS_PASSWORD", "redis-test-password")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("LOG_FORMAT", "json")

	cfg, err := LoadConfig(t.TempDir())
	if err != nil {
		t.Fatalf("LoadConfig() returned an error: %v", err)
	}

	if cfg.ServerPort != "9090" {
		t.Errorf("ServerPort = %q, want %q", cfg.ServerPort, "9090")
	}
	if cfg.MongoURI != "mongodb://localhost:27017" {
		t.Errorf("MongoURI = %q, want %q", cfg.MongoURI, "mongodb://localhost:27017")
	}
	if cfg.DBName != "test_db" {
		t.Errorf("DBName = %q, want %q", cfg.DBName, "test_db")
	}
	if cfg.JWTSecretKey != "test-secret-key" {
		t.Errorf("JWTSecretKey = %q, want %q", cfg.JWTSecretKey, "test-secret-key")
	}
	if cfg.JWTExpirationHours != 48 {
		t.Errorf("JWTExpirationHours = %d, want 48", cfg.JWTExpirationHours)
	}
	if !cfg.EnableCache {
		t.Error("EnableCache = false, want true")
	}
	if cfg.RedisAddr != "localhost:6379" {
		t.Errorf("RedisAddr = %q, want %q", cfg.RedisAddr, "localhost:6379")
	}
	if cfg.RedisPassword != "redis-test-password" {
		t.Errorf("RedisPassword = %q, want %q", cfg.RedisPassword, "redis-test-password")
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel = %q, want %q", cfg.LogLevel, "debug")
	}
	if cfg.LogFormat != "json" {
		t.Errorf("LogFormat = %q, want %q", cfg.LogFormat, "json")
	}
}

func TestLoadConfigDefaults(t *testing.T) {
	envKeys := []string{
		"PORT",
		"ENABLE_CACHE",
		"JWT_EXPIRATION_HOURS",
		"MONGO_URI",
		"DB_NAME",
		"JWT_SECRET_KEY",
		"REDIS_ADDR",
		"REDIS_PASSWORD",
		"LOG_LEVEL",
		"LOG_FORMAT",
	}

	for _, key := range envKeys {
		t.Setenv(key, "")
	}

	cfg, err := LoadConfig(t.TempDir())
	if err != nil {
		t.Fatalf("LoadConfig() returned an error: %v", err)
	}

	if cfg.ServerPort != "8080" {
		t.Errorf("ServerPort = %q, want %q", cfg.ServerPort, "8080")
	}
	if cfg.JWTExpirationHours != 72 {
		t.Errorf("JWTExpirationHours = %d, want 72", cfg.JWTExpirationHours)
	}
	if cfg.EnableCache {
		t.Error("EnableCache = true, want false")
	}
}

func TestLoadConfigFromFile(t *testing.T) {
	configDir := t.TempDir()

	configContent := `
PORT=9091
MONGO_URI=mongodb://localhost:27017
DB_NAME=file_test_db
JWT_SECRET_KEY=file-test-secret
JWT_EXPIRATION_HOURS=24
ENABLE_CACHE=true
LOG_LEVEL=INFO
LOG_FORMAT=json
`

	if err := os.WriteFile(
		filepath.Join(configDir, ".env"),
		[]byte(configContent),
		0600,
	); err != nil {
		t.Fatalf("Failed to create config file: %v", err)
	}

	cfg, err := LoadConfig(configDir)
	if err != nil {
		t.Fatalf("LoadConfig() returned an error: %v", err)
	}

	if cfg.ServerPort != "9091" {
		t.Errorf("ServerPort = %q, want %q", cfg.ServerPort, "9091")
	}
	if cfg.DBName != "file_test_db" {
		t.Errorf("DBName = %q, want %q", cfg.DBName, "file_test_db")
	}
	if cfg.JWTExpirationHours != 24 {
		t.Errorf("JWTExpirationHours = %d, want 24", cfg.JWTExpirationHours)
	}
	if !cfg.EnableCache {
		t.Error("EnableCache = false, want true")
	}
}

func TestLoadConfigEnvironmentOverridesFile(t *testing.T) {
	configDir := t.TempDir()

	configContent := `
PORT=9091
DB_NAME=file_test_db
`

	if err := os.WriteFile(
		filepath.Join(configDir, ".env"),
		[]byte(configContent),
		0600,
	); err != nil {
		t.Fatalf("Failed to create config file: %v", err)
	}

	t.Setenv("PORT", "9095")
	t.Setenv("DB_NAME", "environment_test_db")

	cfg, err := LoadConfig(configDir)
	if err != nil {
		t.Fatalf("LoadConfig() returned an error: %v", err)
	}

	if cfg.ServerPort != "9095" {
		t.Errorf("ServerPort = %q, want %q", cfg.ServerPort, "9095")
	}
	if cfg.DBName != "environment_test_db" {
		t.Errorf("DBName = %q, want %q", cfg.DBName, "environment_test_db")
	}
}

func TestLoadConfigInvalidValue(t *testing.T) {
	configDir := t.TempDir()

	configContent := `
JWT_EXPIRATION_HOURS=not-a-number
`

	if err := os.WriteFile(
		filepath.Join(configDir, ".env"),
		[]byte(configContent),
		0600,
	); err != nil {
		t.Fatalf("Failed to create config file: %v", err)
	}

	_, err := LoadConfig(configDir)
	if err == nil {
		t.Fatal("LoadConfig() expected an error for invalid JWT_EXPIRATION_HOURS, got nil")
	}
}
