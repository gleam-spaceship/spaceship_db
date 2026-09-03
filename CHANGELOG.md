# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-XX

### Added

- Database migration system with sync and async APIs
- Migration tracker table `__spaceship_migrations`
- `migrate()` and `rollback()` for applying/rolling back migrations
- `migrate_async()` and `rollback_async()` for asynchronous operation

### Changed

- Version bumped to 0.2.0

## [0.1.0] - 2024-12-XX

### Added

- Initial release
- SQLite driver with synchronous and asynchronous APIs
- Cloudflare D1 driver
- Turso HTTP driver with baton-based transaction support
- Async transaction API (`async_transaction`, `exec_async_tx`, `commit_async_tx`, `rollback_async_tx`)
- `with_db` and `with_async_db` for automatic connection cleanup
- `prepare`, `exec`, `prepare_async`, `exec_async` for query execution
- `decode_all` and `decode_one` for row decoding
- `get_one` helper for single row queries
