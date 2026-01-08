# Feature Request: UI Overhaul - Adopt NetBox (Tabler) Design System

## 1. Objective

Refactor the current `diagnostic-tools` web interface to mirror the visual style, layout density, and UX patterns of **NetBox**.
The goal is to achieve a professional "Infrastructure Management" look and feel while maintaining the current **Ruby on Rails 7 + Tailwind CSS + Hotwire** technology stack.

> **Constraint:** Do NOT install Bootstrap or Sass. All styling must be implemented using **Tailwind CSS utility classes** to replicate the NetBox/Tabler aesthetic.

## 2. Design System Reference (NetBox Style)

Based on the analysis of the NetBox repository (`netbox-community/netbox`), the target design system has the following characteristics:

### 2.1 Color Palette (Tailwind Mapping)

- **Primary Brand:** NetBox Teal. Use Tailwind `teal-600` for primary buttons, active links, and accents.
- **Background:**
  - App Background: `slate-100` (Light Gray).
  - Content Background: `white`.
  - Sidebar: `slate-900` (Dark Mode) or `white` (Light Mode). Let's stick to **Dark Sidebar** (`slate-800` to `slate-900`) for high contrast.
- **Text:**
  - Headings: `slate-800`.
  - Body: `slate-600`.
  - Muted/Meta: `slate-400`.
- **Status Colors (Crucial for Diagnostics):**
  - Success (Online/Passed): `green-600` (bg-green-100 text-green-700).
  - Warning (Unknown): `yellow-600` (bg-yellow-100 text-yellow-700).
  - Danger (Offline/Failed): `red-600` (bg-red-100 text-red-700).
  - Info: `blue-600` (bg-blue-100 text-blue-700).

### 2.2 Typography

- **Font:** San-serif (Inter or system stack).
- **Size:** Dense. Base font size should be `text-sm` (14px) for data tables to fit more information. Headings should be clear but compact.

### 2.3 Key UI Components (To Mimic)

1.  **Cards:** White background, thin border (`border-slate-200`), slight shadow (`shadow-sm`), distinctive header with a separator line.
2.  **Tables:** "Striped" is optional, but strictly bordered rows (`border-b`), dense padding (`py-2 px-3`), and actionable rows (hover effects) are required.
3.  **Navigation:**
    - **Sidebar:** Collapsible groups, distinctive icons, high contrast text.
    - **Breadcrumbs:** Always present at the top of the content area.
    - **Tabs:** Used heavily for switching between "Details", "Benchmarks", "Logs" within a Node view.

## 3. Implementation Plan

### Phase 1: Layout Skeleton Refactor

**Target File:** `app/views/layouts/application.html.erb` & `app/views/layouts/dashboard.html.erb`

1.  **Structure:** Change the main grid layout to:
    - **Sidebar (Left):** Fixed width (e.g., `w-64`), dark background (`bg-slate-900`), text white/gray.
    - **Navbar (Top):** White background, border bottom, search bar, user profile dropdown.
    - **Main Content (Right):** `bg-slate-100` filling the rest of the screen.
2.  **Footer:** Simple footer with version info (mimicking NetBox footer).

### Phase 2: Sidebar & Navigation

**Target File:** `app/views/shared/_sidebar.html.erb` (Create or refactor existing)

1.  **Styling:**
    - Section Headers: Uppercase, small, muted text (`text-xs font-bold text-slate-500 uppercase tracking-wider`).
    - Links: Flex layout with Icon + Text. Hover state: `bg-slate-800 text-teal-400`.
2.  **Organization:** Group items logically:
    - _Organization:_ Nodes, Clusters (Future).
    - _Benchmarks:_ Recipes, Runs.
    - _Admin:_ Users, API Keys, Settings.

### Phase 3: "Node Details" View (The Core View)

**Target File:** `app/views/nodes/show.html.erb`

Refactor the Node Details page to use the **NetBox Object View** pattern:

1.  **Header:**
    - Left: Title (Node Hostname), Subtitle (UUID/Status Badge).
    - Right: Action Buttons (Edit, Delete, Run Benchmark) styled as specific grouped buttons.
2.  **Body Layout (Grid):**
    - **Left Column (Info):** A "Card" showing key-value pairs (Status, IP, OS, Kernel, SSH Info).
    - **Right Column (Metrics/Activity):** A "Card" showing the Heatmap or Sparklines.
    - **Bottom Section:** A specialized "Related Objects" table (Recent Benchmark Runs).
3.  **Tabs:** Implement a Tab system (using Stimulus or pure CSS target hack) to switch between:
    - Overview (Info + Stats)
    - Hardware (Inventory details)
    - Benchmark History
    - Logs (Agent Stream)

### Phase 4: Data Tables Styling

**Target File:** `app/views/nodes/_table.html.erb` and `app/views/benchmark_runs/index.html.erb`

Apply a global style for all index tables:

- **Header:** `bg-slate-50 text-slate-500 text-xs font-medium uppercase tracking-wider border-b border-slate-200`.
- **Rows:** `bg-white border-b border-slate-200 hover:bg-slate-50 transition duration-150`.
- **Cells:** `text-sm text-slate-700`.
- **Actions:** Right-aligned column with "Edit/Delete" icon buttons (ghost style).

### Phase 5: Forms (Settings & Input)

**Target File:** `app/components/node_form_component.html.erb`

1.  **Input Groups:** Use standard Tailwind forms plugin styles but ensure labels are strictly above inputs (`block text-sm font-medium text-slate-700 mb-1`).
2.  **Help Text:** Small muted text below inputs.
3.  **Sections:** Divide long forms (like Node Create) into Fieldsets with Legends, mimicking NetBox's form segments.

## 4. Specific Component Instructions

### Status Badges (Helper Refactor)

Refactor `node_status_badge` helper to output Tailwind classes mimicking NetBox labels:

- `online`: `bg-emerald-500 text-white px-2 py-0.5 rounded text-xs font-bold shadow-sm`
- `offline`: `bg-red-500 text-white ...`
- `running`: `bg-blue-500 text-white animate-pulse ...`

### Buttons

- **Primary Action (Create/Run):** `bg-teal-600 hover:bg-teal-700 text-white font-medium py-2 px-4 rounded shadow-sm focus:ring-2 focus:ring-teal-500`.
- **Secondary Action (Cancel/Back):** `bg-white border border-slate-300 text-slate-700 hover:bg-slate-50 ...`.
- **Danger Action (Delete):** `text-red-600 hover:bg-red-50 border border-transparent ...`.

## 5. Acceptance Criteria

1.  The application must look visually consistent with NetBox v4.0+.
2.  No SCSS or Bootstrap files are added; `tailwind.config.js` manages all design tokens.
3.  The sidebar navigation is present on all Dashboard/Admin pages.
4.  Mobile responsiveness is maintained (Sidebar collapses into a hamburger menu).
5.  Hotwire (Turbo Frames/Streams) functionality remains intact (e.g., log streaming, status updates).
