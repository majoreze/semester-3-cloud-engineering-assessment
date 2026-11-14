package config

import (
	"github.com/spf13/viper"
)

// Config stores all configuration of the application.
type Config struct {
	ServerPort         string `mapstructure:"PORT"`
	MongoURI           string `mapstructure:"MONGO_URI"`
	DBName             string `mapstructure:"DB_NAME"`
	JWTSecretKey       string `mapstructure:"JWT_SECRET_KEY"`
	JWTExpirationHours int    `mapstructure:"JWT_EXPIRATION_HOURS"`
	EnableCache        bool   `mapstructure:"ENABLE_CACHE"`
	RedisAddr          string `mapstructure:"REDIS_ADDR"`
	RedisPassword      string `mapstructure:"REDIS_PASSWORD"`
	LogLevel           string `mapstructure:"LOG_LEVEL"`
	LogFormat          string `mapstructure:"LOG_FORMAT"`
}

// LoadConfig reads configuration from file or environment variables.
func LoadConfig(path string) (config Config, err error) {
	// Use a new Viper instance for each configuration load.
	v := viper.New()

	v.AddConfigPath(path)
	v.SetConfigName(".env")
	v.SetConfigType("env")
	v.AutomaticEnv()

	// Explicitly bind environment variables for struct unmarshalling.
	envKeys := []string{
		"PORT",
		"MONGO_URI",
		"DB_NAME",
		"JWT_SECRET_KEY",
		"JWT_EXPIRATION_HOURS",
		"ENABLE_CACHE",
		"REDIS_ADDR",
		"REDIS_PASSWORD",
		"LOG_LEVEL",
		"LOG_FORMAT",
	}

	for _, key := range envKeys {
		if err = v.BindEnv(key, key); err != nil {
			return config, err
		}
	}

	// Default values.
	v.SetDefault("PORT", "8080")
	v.SetDefault("ENABLE_CACHE", false)
	v.SetDefault("JWT_EXPIRATION_HOURS", 72)

	// Read configuration file if one exists.
	err = v.ReadInConfig()
	if err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return config, err
		}
	}

	// Map configuration values into the Config struct.
	if err = v.Unmarshal(&config); err != nil {
		return config, err
	}

	return config, nil
}
