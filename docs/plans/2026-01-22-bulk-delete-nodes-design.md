# Bulk Delete Nodes Design

## Overview

Add multi-select functionality to the nodes table, allowing approvers to delete multiple nodes at once.

## UI Behavior

- Checkboxes visible only to approvers (consistent with existing delete permissions)
- Header checkbox for "Select All" with three states: unchecked, checked, indeterminate
- Action bar appears automatically when 1+ nodes selected
- Action bar shows count and provides "Delete Selected" and "Clear" buttons
- Simple browser confirm dialog before deletion (matches existing single-delete UX)

### Visual Design

```
Default state (clean):
┌─────────────────────────────────────────────────────────────────────┐
│  Nodes                                              [Add Node]      │
├─────────────────────────────────────────────────────────────────────┤
│  ☐  │ Hostname        │ Role    │ Arch   │ Status  │ Actions       │
├─────────────────────────────────────────────────────────────────────┤
│  ☐  │ node01.local    │ Compute │ x86_64 │ ● Online│ [icons...]    │
│  ☐  │ node02.local    │ Compute │ x86_64 │ ○ Offline│ [icons...]   │
└─────────────────────────────────────────────────────────────────────┘

When 1+ selected (action bar appears):
┌─────────────────────────────────────────────────────────────────────┐
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  2 nodes selected              [Delete Selected] [Clear]      │  │
│  └───────────────────────────────────────────────────────────────┘  │
│  Nodes                                              [Add Node]      │
├─────────────────────────────────────────────────────────────────────┤
│  ☑  │ Hostname        │ Role    │ Arch   │ Status  │ Actions       │
├─────────────────────────────────────────────────────────────────────┤
│  ☑  │ node01.local    │ Compute │ x86_64 │ ● Online│ [icons...]    │
│  ☑  │ node02.local    │ Compute │ x86_64 │ ○ Offline│ [icons...]   │
│  ☐  │ admin01.local   │ Admin   │ x86_64 │ ● Online│ [icons...]    │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Stimulus Controller: `bulk_select_controller.js`

**Targets:**
- `actionBar`: floating bar that appears when items selected
- `count`: span showing "X nodes selected"
- `checkbox`: all row checkboxes (multiple)
- `selectAll`: header checkbox
- `form`: the delete form
- `hiddenInputs`: container for dynamic hidden inputs

**State:**
- `selectedIds`: Set of selected node IDs

**Actions:**
- `toggle(event)`: Add/remove ID from selection, update UI
- `toggleAll(event)`: Select all or none based on header checkbox
- `clearAll()`: Deselect everything, hide action bar
- `deleteSelected()`: Populate hidden inputs and submit form

**Header checkbox states:**
- `checked = false` when none selected
- `checked = true` when all selected
- `indeterminate = true` when some (but not all) selected

### 2. View Changes

**`app/views/nodes/_table.html.erb`:**
- Wrap table in `data-controller="bulk-select"`
- Add action bar div (hidden by default)
- Add checkbox column in header (approvers only)

**`app/views/nodes/_node.html.erb`:**
- Add checkbox cell as first column (approvers only)
- Checkbox includes `data-bulk-select-target="checkbox"` and `data-node-id`

### 3. Backend

**Route:**
```ruby
resources :nodes do
  collection do
    delete :bulk_destroy
  end
end
```

**Controller action in `NodesController`:**
```ruby
def bulk_destroy
  node_ids = params[:node_ids] || []
  @deleted_nodes = Node.where(id: node_ids)
  deleted_count = @deleted_nodes.destroy_all.count

  respond_to do |format|
    format.turbo_stream {
      flash.now[:notice] = "#{deleted_count} nodes deleted."
    }
    format.html {
      redirect_to nodes_path, notice: "#{deleted_count} nodes deleted."
    }
  end
end
```

**Turbo Stream response (`bulk_destroy.turbo_stream.erb`):**
```erb
<% @deleted_nodes.each do |node| %>
  <%= turbo_stream.remove node %>
<% end %>
<%= turbo_stream.update "flash_messages", partial: "shared/flash" %>
```

## Security

- `bulk_destroy` added to `authorize_approver!` before_action
- Checkboxes only rendered for approvers
- `Node.where(id: node_ids)` safely ignores invalid IDs

## Edge Cases

- Empty selection: Submit button disabled when nothing selected
- Invalid IDs: Silently ignored by ActiveRecord query
- Partial failure: Response shows actual count deleted

## Files to Create/Modify

1. `app/javascript/controllers/bulk_select_controller.js` (new)
2. `app/views/nodes/_table.html.erb` (modify)
3. `app/views/nodes/_node.html.erb` (modify)
4. `app/controllers/nodes_controller.rb` (modify)
5. `app/views/nodes/bulk_destroy.turbo_stream.erb` (new)
6. `config/routes.rb` (modify)
7. `spec/requests/nodes_spec.rb` (modify - add tests)
