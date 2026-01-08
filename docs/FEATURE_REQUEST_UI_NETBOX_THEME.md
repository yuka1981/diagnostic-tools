# Feature Request: UI Theme Migration (NetBox Style)

## 🎯 Objective

Replace the current generic web UI theme of `diagnostic-tools` with a strict visual replica of **NetBox v4.0+**.
The goal is to achieve the professional "Infrastructure Source of Truth" aesthetic while adhering to the existing **Ruby on Rails 7 + Tailwind CSS** technology stack.

> **Constraint:** Do NOT introduce Bootstrap, Sass, or Tabler.io CSS files. All styling must be implemented using **pure Tailwind CSS utility classes** to mimic the design tokens of NetBox.

## 🎨 Design System & Tokens (The "NetBox Look")

Reference the uploaded NetBox codebase (`netbox/project-static/styles/_variables.scss`) for design intuition.

### 1. Color Palette Mapping

Implement these exact mappings in Tailwind classes:

| UI Element        | NetBox Context        | Target Tailwind Class           | Hex Approximation |
| ----------------- | --------------------- | ------------------------------- | ----------------- |
| **Brand Primary** | Buttons, Active Links | `bg-teal-600` / `text-teal-600` | `#0097a7`         |
| **Sidebar Bg**    | Left Navigation       | `bg-slate-900`                  | `#242e42`         |
| **Sidebar Text**  | Inactive Links        | `text-slate-400`                | `#9ca3af`         |
| **Sidebar Hover** | Active/Hover Link     | `bg-slate-800 text-teal-400`    | --                |
| **Page Bg**       | App Background        | `bg-slate-100`                  | `#f1f5f9`         |
| **Card Bg**       | Content Containers    | `bg-white`                      | `#ffffff`         |
| **Border**        | Tables, Separators    | `border-slate-300`              | `#cbd5e1`         |

### 2. Status Colors (Critical for Diagnostics)

NetBox uses distinct colors for object states. Map `Node` statuses to these:

- **Active/Online:** `bg-green-100 text-green-800` (Badge)
- **Offline/Down:** `bg-red-100 text-red-800`
- **Staged/Provisioning:** `bg-blue-100 text-blue-800`
- **Warning/Metric Alert:** `bg-yellow-100 text-yellow-800`

### 3. Typography

- **Font Family:** Use strict sans-serif. Prefer `Inter` if available, otherwise system stack.
- **Density:** NetBox is data-dense. Use `text-sm` (14px) as the default for tables and lists, not `text-base`.

---

## 🛠 Implementation Tasks

### Step 1: Global Layout Refactor

**Target:** `app/views/layouts/application.html.erb` & `app/views/layouts/dashboard.html.erb`

Refactor the main grid to match NetBox's "Sidebar + Header + Main Content" layout:

1. **Sidebar (Fixed Left):** width `16rem` (64), background `slate-900`.
2. **Top Header (Sticky):** White background, border-bottom `slate-200`, flex container for Search and User Menu.
3. **Main Content Area:** Background `slate-100`, strictly padded (`p-4` or `p-6`).
4. **Breadcrumbs:** Must be present at the top of every resource page (e.g., `Home / Nodes / node-01`).

### Step 2: Sidebar Component (`_sidebar.html.erb`)

**Target:** `app/views/shared/_sidebar.html.erb`

Rebuild the sidebar to match `netbox/templates/inc/navigation/menu.html`:

- **Sections:** Group links with uppercase, muted headers (e.g., "ORGANIZATION", "OBSERVABILITY").
- **Links:** Flex layout, Icon (left) + Label.
- **Search:** Add the global search bar at the top of the sidebar (or top nav, depending on NetBox v3 vs v4 preference. _Target v4 style: Search in Top Nav_).

### Step 3: Card Component & Object Views

**Target:** `app/views/nodes/show.html.erb`

Transform the "Node Details" page to look like a NetBox Device view (`netbox/templates/dcim/device.html`):

1. **Page Header:** Large Title (Hostname) + Badge (Status) + Action Buttons (Right aligned: Edit, Delete, Connect).
2. **Panel Grid:** Use CSS Grid (`grid-cols-12`).

- **Info Panel (Left, col-span-6):** A card (`bg-white shadow-sm border border-slate-300 rounded`) containing a striped table of attributes (IP, OS, Kernel).
- **Stats/Hardware Panel (Right, col-span-6):** A card for CPU/Memory metrics.

3. **Tabs:** Implement a tab bar below the header: "Overview", "Interfaces", "Benchmarks", "Logs".

### Step 4: Data Tables Styling

**Target:** `app/views/nodes/_table.html.erb`, `app/views/benchmark_runs/index.html.erb`

Mimic `netbox/templates/inc/table.html`:

- **Container:** `border border-slate-300 rounded overflow-hidden`.
- **Header:** `bg-slate-50 text-xs font-bold text-slate-500 uppercase tracking-wider py-2 px-3 border-b`.
- **Rows:** `bg-white hover:bg-teal-50 border-b border-slate-200`.
- **Typography:** `text-sm text-slate-700`.
- **Action Column:** Right-aligned, minimal icons (Pencil/Trash) using strictly `text-slate-400 hover:text-blue-600`.

### Step 5: Form Styling

**Target:** `app/components/node_form_component.html.erb`

Mimic NetBox forms (`netbox/templates/generic/object_edit.html`):

- **Field Groups:** `mb-4`.
- **Labels:** `block text-sm font-bold text-slate-700 mb-1`.
- **Inputs:** `w-full rounded border-slate-300 focus:border-teal-500 focus:ring-teal-500 sm:text-sm`.
- **Help Text:** `text-xs text-slate-500 mt-1`.

---

## 🔍 Validation Checklist

The AI Agent must verify:

1. [ ] **No Bootstrap dependencies** are found in `Gemfile` or `package.json`.
2. [ ] The "Create Node" button uses the specific Tailwind class `bg-teal-600`.
3. [ ] The Sidebar is dark mode (`bg-slate-900`) regardless of the user's OS preference (NetBox default).
4. [ ] Tables have dense padding (`py-2`) to maximize information density.

## 📂 Reference Files (Source of Truth)

Use these files from the uploaded context to understand the _content_ and _structure_ we are mimicking:

- `netbox/templates/base/layout.html` (Layout reference)
- `netbox/project-static/styles/_variables.scss` (Color reference)
- `netbox/templates/dcim/device.html` (Object view reference)
- `netbox/templates/inc/table.html` (Table style reference)
