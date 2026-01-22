# Lucide Icons Integration Design

## Overview

Replace all existing inline Heroicons with Lucide icons across the application using a centralized helper method and YAML configuration.

## Motivation

Design preference - Lucide's aesthetic is preferred over Heroicons.

## Technical Approach

### Helper Implementation

**File: `app/helpers/lucide_helper.rb`**

```ruby
module LucideHelper
  def lucide_icon(name, options = {})
    icon_data = lucide_icons[name.to_s]
    return content_tag(:span, "?", title: "Unknown icon: #{name}") unless icon_data

    css_class = options.delete(:class) || "w-5 h-5"

    content_tag(:svg,
      class: css_class,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": options.delete(:stroke_width) || 2,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      **options
    ) do
      icon_data["paths"].map { |d| tag(:path, d: d) }.reduce(:+)
    end
  end

  private

  def lucide_icons
    @lucide_icons ||= YAML.load_file(Rails.root.join("config/lucide_icons.yml"))
  end
end
```

**Usage:**
```erb
<%= lucide_icon("server", class: "h-5 w-5 opacity-75") %>
<%= lucide_icon("settings", class: "h-6 w-6 text-slate-400") %>
```

### YAML Configuration

**File: `config/lucide_icons.yml`**

Store SVG path data for each icon:

```yaml
layout-dashboard:
  paths:
    - "M3 9h18"
    - "M9 3v18"
    - "M3 3h18v18H3z"

server:
  paths:
    - "M2 9a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9Z"
    - "..."
```

## Icon Mapping

| Location | Current Icon | Lucide Equivalent |
|----------|-------------|-------------------|
| Brand logo | server stack | `server` |
| Dashboard | grid squares | `layout-dashboard` |
| Sites | building | `building-2` |
| Rooms | box | `warehouse` |
| Racks | server | `server` |
| Nodes | server | `hard-drive` |
| Benchmark Runs | bar chart | `bar-chart-3` |
| Recipes | flask | `flask-conical` |
| API Keys | key | `key` |
| SSH Settings | lock | `lock` |
| SSH Profiles | key | `key-round` |
| Agent Config | gear | `settings` |
| Server Products | server | `server` |
| Sign out | arrow right | `log-out` |
| Sign in | arrow left | `log-in` |
| Status: success | check circle | `circle-check` |
| Status: failed | x circle | `circle-x` |
| Status: running | spinner | `loader-2` |
| Status: pending | clock | `clock` |

## Files to Modify

### New Files
- `app/helpers/lucide_helper.rb`
- `config/lucide_icons.yml`

### Files to Update
1. `app/views/shared/_sidebar.html.erb` - 15 icons
2. `app/helpers/application_helper.rb` - `status_icon` method
3. `app/views/notifications/icons/` - 4 partials (may be removed)
4. Additional view files with inline SVGs

## Implementation Steps

1. Create `lucide_helper.rb` with helper method
2. Create `lucide_icons.yml` with all needed icon paths
3. Include `LucideHelper` in `ApplicationHelper`
4. Update `_sidebar.html.erb` (highest icon density)
5. Update `application_helper.rb` status methods
6. Scan and update remaining views
7. Remove unused notification icon partials

## Verification

1. `bin/rspec` - no test failures
2. `bin/rubocop` - helper passes linting
3. Visual check - all icons render in sidebar
4. Browser console - no SVG errors

No new tests needed - icons are presentational and existing specs cover rendering.
