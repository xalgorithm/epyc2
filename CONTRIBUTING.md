# Contributing to Kubernetes Infrastructure on Proxmox

Thank you for your interest in contributing to this project! This document provides guidelines and information for contributors.

## 🤝 How to Contribute

### Reporting Issues
- Use the GitHub issue tracker to report bugs or request features
- Provide detailed information about your environment and steps to reproduce
- Include relevant logs and error messages
- Check existing issues to avoid duplicates

### Submitting Changes
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes following the project standards
4. Test your changes thoroughly
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📋 Development Guidelines

### Code Standards

#### Terraform
- Use consistent formatting (`terraform fmt`)
- Include meaningful variable descriptions
- Use appropriate variable types and validation
- Follow HashiCorp's Terraform style guide
- Include examples in variable descriptions

#### Shell Scripts
- Use `#!/bin/bash` shebang
- Include `set -e` for error handling
- Use meaningful variable names
- Include help/usage functions
- Add comments for complex logic
- Use consistent formatting and indentation

#### Documentation
- Write clear, concise documentation
- Include practical examples
- Update relevant documentation when making changes
- Follow the existing documentation structure
- Test all documented procedures

### Project Structure

```
├── docs/                     # All documentation
│   ├── deployment/          # Deployment guides
│   ├── backup/              # Backup documentation
│   ├── monitoring/          # Monitoring setup
│   └── troubleshooting/     # Issue resolution
├── scripts/                 # Automation scripts
│   ├── deployment/          # Deployment automation
│   ├── backup/              # Backup operations
│   ├── maintenance/         # System maintenance
│   └── troubleshooting/     # Diagnostic tools
├── configs/                 # Configuration files
│   ├── grafana/            # Grafana dashboards/configs
│   ├── prometheus/         # Prometheus configurations
│   └── backup/             # Backup configurations
└── *.tf                    # Terraform infrastructure files
```

### Testing Requirements

#### Before Submitting
- Test all Terraform configurations with `terraform plan`
- Validate all shell scripts with `shellcheck` (if available)
- Test deployment scripts in a development environment
- Verify documentation accuracy
- Ensure all scripts have proper error handling

#### Infrastructure Testing
- Test infrastructure deployment from scratch
- Verify all components are functional
- Test backup and restore procedures
- Validate monitoring and alerting
- Check ingress and networking functionality

## 🔧 Development Environment

### Prerequisites
- Terraform 1.0+
- Access to Proxmox VE environment
- SSH key pair for VM access
- Basic understanding of Kubernetes
- Familiarity with shell scripting

### Setup
1. Clone the repository
2. Copy `terraform.tfvars.example` to `terraform.tfvars`
3. Configure your environment variables
4. Run pre-flight checks: `./scripts/deployment/pre-flight-check.sh`

### Testing Changes
1. Use a separate Proxmox environment for testing
2. Test the complete deployment process
3. Verify all components are working
4. Test backup and restore functionality
5. Document any new procedures or changes

## 📝 Documentation Standards

### Writing Guidelines
- Use clear, concise language
- Include step-by-step instructions
- Provide working code examples
- Add troubleshooting sections
- Cross-reference related documents

### Documentation Types

#### Deployment Guides
- Prerequisites and requirements
- Step-by-step procedures
- Verification steps
- Common issues and solutions

#### Troubleshooting Guides
- Problem description and symptoms
- Root cause analysis
- Solution procedures
- Prevention measures

#### Configuration Guides
- Purpose and overview
- Configuration options
- Examples and best practices
- Integration with other components

## 🐛 Bug Reports

### Information to Include
- **Environment Details**: Proxmox version, Terraform version, OS
- **Steps to Reproduce**: Exact steps that led to the issue
- **Expected Behavior**: What should have happened
- **Actual Behavior**: What actually happened
- **Logs and Errors**: Relevant log entries and error messages
- **Configuration**: Relevant parts of your terraform.tfvars (sanitized)

### Bug Report Template
```markdown
## Bug Description
Brief description of the issue.

## Environment
- Proxmox VE Version: 
- Terraform Version: 
- Operating System: 
- Project Version/Commit: 

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen.

## Actual Behavior
What actually happens.

## Logs and Error Messages
```
Paste relevant logs here
```

## Additional Context
Any other relevant information.
```

## 🚀 Feature Requests

### Information to Include
- **Use Case**: Why is this feature needed?
- **Proposed Solution**: How should it work?
- **Alternatives**: Other ways to achieve the same goal
- **Implementation Ideas**: Technical approach (if you have ideas)

## 🔍 Code Review Process

### What We Look For
- **Functionality**: Does the code work as intended?
- **Quality**: Is the code well-written and maintainable?
- **Testing**: Has the code been properly tested?
- **Documentation**: Is the code properly documented?
- **Standards**: Does the code follow project standards?

### Review Criteria
- Code follows project conventions
- Changes are well-tested
- Documentation is updated
- No breaking changes without justification
- Security considerations are addressed

## 📚 Resources

### Learning Resources
- [Terraform Documentation](https://www.terraform.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [K3s Documentation](https://rancher.com/docs/k3s/latest/en/)

### Project-Specific Resources
- [Project Documentation](docs/)
- [Deployment Guide](docs/deployment/DEPLOYMENT-GUIDE.md)
- [Troubleshooting Guides](docs/troubleshooting/)

## 🏷️ Release Process

### Version Numbering
We follow [Semantic Versioning](https://semver.org/):
- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist
- [ ] All tests pass
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated
- [ ] Version numbers are bumped
- [ ] Release notes are prepared

## 📞 Getting Help

### Community Support
- GitHub Issues for bug reports and feature requests
- GitHub Discussions for questions and community support

### Maintainer Contact
- Create an issue for project-related questions
- Use discussions for general questions about usage

## 🙏 Recognition

Contributors will be recognized in:
- Project README.md
- Release notes
- CHANGELOG.md

Thank you for contributing to making this project better! 🎉