---
title: Introduce Security plugin versioning strategy
date: 2023-03-28
area: system-settings
tags: [architecture, workflow, structure, security]
---

## Context

As the release of a new major version of Shopware 6.5, we need to make this plugin compatible with the newest Shopware version. 

In other extensions, when we introduce a new major version, we could just drop support for the old Shopware version. However, due to the technical requirement of the security plugin, a new fix should be applicable for as many Shopware 6 versions as possible.
This leads to a complicated/messy code base where the new major deprecated/removed a lot of services/classes and introduced alternative ones, using the new PHP8 features, using new CI templates, deployments, etc. 

Making it compatible with 6.5 and older versions at the same code base might cost a lot of effort for the developers to maintain the plugin properly.

## Decision

We came to the final decision to introduce a new versioning strategy for the security plugin, following these criteria:

### 2.x version for 6.5 compatible:

- We use the `trunk` branch for `2.x` version
- Increase the version in composer.json to `2.0.0` and requires `"shopware/core": "~6.5.0"`
- Remove all existing fixes (as none should be relevant for 6.5)
- Make the general structure compatible with 6.5
- Apply PHP8 syntax
- For easier to develop, when adding a new fix the steps are the same as in `1.x`

### 1.x version for 6.1 - 6.4 compatible

- We use the `6.4` branch for the `1.x` version
- Leave the code base the same

## Consequences

When implementing a new security fix, if it's relevant to the older Shopware 6 versions (6.1 - 6.4), we should create two MR into the `6.4` and `trunk` branches accordingly. Otherwise, the new fix should be merged into the `trunk` branch only. 

| Shopware version range affected | MR to `trunk` (2.x) | MR to `6.4` (1.x) |
|---------------------------------|---------------------|-------------------|
| 6.1 - 6.4                       | ❌                   | ✅                 |
| 6.1 - >= 6.5                    | ✅                   | ✅                 |
| >= 6.5                          | ✅                   | ❌                 |
