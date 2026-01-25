# Task Row Expansion Transition Design

## Overview

Add a smooth slide-down transition when users expand task rows on the tasks index page.

## Current Behavior

- Clicking a task row toggles the `hidden` class on the details row
- Details appear/disappear instantly with no animation
- Chevron icon already has a rotation transition

## Desired Behavior

- Details row smoothly slides down when expanded
- Details row smoothly slides up when collapsed
- Transition duration: 200ms
- Easing: ease-out

## Technical Approach

Use CSS Grid animation (`grid-template-rows: 0fr → 1fr`) because:
- Pure CSS with Tailwind classes
- Smooth regardless of content height
- No JavaScript height calculations needed
- Well-supported in modern browsers

### How It Works

Wrap content in two nested divs:
- Outer div: `display: grid` with `grid-template-rows` transition
- Inner div: `overflow: hidden` to clip content during animation

```html
<tr>  <!-- No 'hidden' class -->
  <td class="p-0">
    <div class="grid grid-rows-[0fr] transition-[grid-template-rows] duration-200 ease-out">
      <div class="overflow-hidden">
        <div class="px-6 py-4">
          <!-- content -->
        </div>
      </div>
    </div>
  </td>
</tr>
```

When expanded, toggle `grid-rows-[0fr]` → `grid-rows-[1fr]`.

## Files to Change

### 1. `app/views/tasks/_task_details.html.erb`

- Remove `hidden` class from `<tr>`
- Change `<td>` padding from `px-6 py-4` to `p-0`
- Add grid wrapper div with transition classes
- Add overflow-hidden wrapper div
- Move padding to innermost content div

### 2. `app/javascript/controllers/accordion_controller.js`

Update `toggle()` method:
- Find grid wrapper inside details element
- Toggle `grid-rows-[1fr]` / `grid-rows-[0fr]` classes instead of `hidden`

Update `closeAll()` method:
- Same grid class toggling logic

## Testing

Existing E2E tests should continue to pass. The tests check for:
- Details row visibility (will need adjustment since `hidden` class is removed)
- Chevron rotation
- Exclusive mode behavior

Tests may need updates to check for `grid-rows-[1fr]` instead of absence of `hidden` class.
