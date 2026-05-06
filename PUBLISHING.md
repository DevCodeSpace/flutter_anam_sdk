# Publishing Guide for Flutter Anam SDK

This guide will help you publish your Flutter library to pub.dev and use it in other projects.

## Prerequisites

1. **Dart SDK**: Make sure you have the latest stable Dart SDK installed
2. **Flutter SDK**: Ensure Flutter is properly installed and configured
3. **pub.dev Account**: Create an account at [pub.dev](https://pub.dev) if you don't have one
4. **Google Account**: You'll need a Google account to publish to pub.dev

## Step 1: Prepare Your Library

### 1.1 Update pubspec.yaml

Make sure your `pubspec.yaml` has all the necessary fields:

- `name`: Unique package name
- `description`: Clear description
- `version`: Semantic versioning
- `homepage`: Link to your repository
- `repository`: Source code location
- `issue_tracker`: Where to report issues
- `documentation`: Documentation link

### 1.2 Verify Library Structure

Ensure your library has:

- Main library file (`lib/flutter_anam_sdk.dart`)
- Proper exports for all public APIs
- Example app in `/example` folder
- Comprehensive README.md
- CHANGELOG.md
- LICENSE file

### 1.3 Run Tests

```bash
flutter test
```

### 1.4 Analyze Code

```bash
flutter analyze
```

## Step 2: Publish to pub.dev

### 2.1 Login to pub.dev

```bash
dart pub login
```

### 2.2 Verify Package

```bash
dart pub publish --dry-run
```

This will check for common issues without actually publishing.

### 2.3 Publish Package

```bash
dart pub publish
```

## Step 3: Using Your Library in Other Projects

### 3.1 Add Dependency

In your other Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  flutter_anam_sdk: ^0.0.1
```

### 3.2 Get Dependencies

```bash
flutter pub get
```

### 3.3 Import and Use

```dart
import 'package:flutter_anam_sdk/flutter_anam_sdk.dart';

// Use your library
final client = AnamClientFactory.createClient(
  sessionToken: 'your-session-token',
);
```

## Step 4: Local Development and Testing

### 4.1 Path Dependencies (Development)

During development, you can use path dependencies:

```yaml
dependencies:
  flutter_anam_sdk:
    path: ../flutter_anam_sdk
```

### 4.2 Git Dependencies

You can also use git dependencies:

```yaml
dependencies:
  flutter_anam_sdk:
    git:
      url: https://github.com/yourusername/flutter_anam_sdk.git
      ref: main
```

## Step 5: Version Management

### 5.1 Semantic Versioning

Follow semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

### 5.2 Update Version

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Commit changes
4. Tag the release
5. Publish

### 5.3 Example Version Update

```yaml
# pubspec.yaml
version: 0.0.1
```

```markdown
# CHANGELOG.md

## 0.0.1

- Added new feature X
- Fixed bug Y
- Breaking change: Renamed method Z
```

## Step 6: Maintenance

### 6.1 Monitor Issues

- Check pub.dev for package health
- Respond to issues on GitHub
- Update dependencies regularly

### 6.2 Update Dependencies

```bash
flutter pub upgrade
flutter pub outdated
```

### 6.3 Breaking Changes

When making breaking changes:

1. Increment MAJOR version
2. Document changes clearly
3. Provide migration guide
4. Consider deprecation warnings

## Troubleshooting

### Common Issues

1. **Package Name Already Taken**
   - Choose a different name
   - Use your organization as prefix (e.g., `com_company_anam_sdk`)

2. **Analysis Issues**
   - Fix all linter warnings
   - Ensure code follows Dart conventions

3. **Dependency Conflicts**
   - Check for conflicting package versions
   - Use dependency_overrides if necessary

4. **Publishing Errors**
   - Check pubspec.yaml syntax
   - Ensure all required fields are present
   - Verify package structure

## Best Practices

1. **Documentation**: Keep README and API docs up to date
2. **Examples**: Provide working examples
3. **Testing**: Maintain good test coverage
4. **Versioning**: Follow semantic versioning strictly
5. **Breaking Changes**: Minimize breaking changes, document them well
6. **Support**: Respond to issues and questions promptly

## Resources

- [Dart Package Publishing](https://dart.dev/guides/publishing)
- [Flutter Package Publishing](https://flutter.dev/docs/development/packages-and-plugins/developing-packages)
- [pub.dev](https://pub.dev)
- [Semantic Versioning](https://semver.org/)
