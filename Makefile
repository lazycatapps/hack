# Example Makefile for a LazyCAT Apps project
# Copy this file to your project and customize the variables below

# Project configuration
# PROJECT_NAME ?= your-project  # defaults to current directory name
# Project type (lpk-only | docker-lpk)
PROJECT_TYPE ?= docker-lpk

# Version (optional, auto-detected from git if not set)
# VERSION := 1.0.0

# Docker configuration (only for docker-lpk projects)
# REGISTRY := docker.io/lazycatapps
# IMAGE_NAME := $(PROJECT_NAME)

# Include the common base.mk
include base.mk

# You can add custom targets below
# Example:
# .PHONY: custom-target
# custom-target: ## My custom target
#	@echo "Running custom target"
