package server

import "github.com/caritos/stark/internal/config"

func configDev() config.Config { return config.Config{PublicOrigin: "https://app.example"} }
