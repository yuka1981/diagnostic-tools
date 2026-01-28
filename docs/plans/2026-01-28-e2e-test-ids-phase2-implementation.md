# E2E Test IDs Phase 2: Auth Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Devise authentication views to enable Playwright E2E testing.

**Architecture:** Each view adds `data-testid` attributes directly to key elements. Test IDs follow the `auth-{element}-{descriptor}` pattern defined in the design document.

**Tech Stack:** Rails 7, Devise, ERB templates

---

## Task 1: Login View (sessions/new)

**Files:**
- Modify: `app/views/devise/sessions/new.html.erb`

**Step 1: Add test IDs to the login form**

In `app/views/devise/sessions/new.html.erb`, add the following `data-testid` attributes:

| Element | Test ID |
|---------|---------|
| Container div (line 3) | `auth-container` |
| Logo image (line 6) | `auth-logo` |
| Login tab link (line 16) | `auth-tab-login` |
| Sign Up tab link (line 18) | `auth-tab-signup` |
| Flash alert div (line 24) | `auth-flash-alert` |
| Form element (line 29) | `auth-form-login` |
| Email input (line 35) | `auth-input-email` |
| Password input (line 46) | `auth-input-password` |
| Password visibility button (line 51) | `auth-button-password-toggle` |
| Submit button (line 71) | `auth-button-submit` |
| Forgot password link (line 79) | `auth-link-forgot-password` |
| Create account link (line 82) | `auth-link-sign-up` |
| Need help link (line 87) | `auth-link-help` |

**Step 2: Apply the changes**

Update `app/views/devise/sessions/new.html.erb`:

```erb
<% content_for(:title) { "Sign In - QCT InfraScope" } %>

<div class="w-full max-w-[472px] bg-white p-9 shadow-lg" data-controller="tabs" data-testid="auth-container">
  <%# QCT Logo %>
  <div class="flex justify-center py-4">
    <%= image_tag "qct_logo_login.svg", alt: "QCT", class: "h-[94px] w-[340px]", data: { testid: "auth-logo" } %>
  </div>

  <%# Subtitle %>
  <div class="flex justify-center mt-4 mb-6">
    <span class="text-2xl font-bold text-neutral-60">InfraScope</span>
  </div>

  <%# Login / Sign Up Tabs %>
  <div class="flex items-center justify-center gap-2 mb-6">
    <%= link_to "Login", new_user_session_path,
        class: "px-3 py-2 text-sm font-medium text-primary-6 border-b-[3px] border-primary-6 transition-all duration-200",
        data: { testid: "auth-tab-login" } %>
    <%= link_to "Sign Up", new_user_registration_path,
        class: "px-3 py-2 text-sm font-normal text-neutral-60 hover:text-primary-6 border-b-[3px] border-transparent transition-all duration-200",
        data: { testid: "auth-tab-signup" } %>
  </div>

  <%# Flash Alert for failed login %>
  <% if flash[:alert].present? %>
    <div class="bg-error-1 border border-error-3 text-error-8 px-4 py-3 rounded-[5px] text-sm mb-6" data-testid="auth-flash-alert">
      <%= flash[:alert] %>
    </div>
  <% end %>

  <%= form_for(resource, as: resource_name, url: session_path(resource_name), html: { class: "space-y-6", data: { testid: "auth-form-login" } }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <%# Account Field %>
    <div class="space-y-2">
      <label class="block text-sm font-medium text-neutral-60">Account</label>
      <%= f.email_field :email,
          autofocus: true,
          autocomplete: "email",
          placeholder: "Enter account",
          data: { testid: "auth-input-email" },
          class: "w-full bg-neutral-2 border border-neutral-8 rounded-[5px] p-3 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
    </div>

    <%# Password Field %>
    <div class="space-y-2" data-controller="password-visibility">
      <label class="block text-sm font-medium text-neutral-60">Password</label>
      <div class="relative">
        <%= f.password_field :password,
            autocomplete: "current-password",
            placeholder: "Enter password",
            data: { password_visibility_target: "input", testid: "auth-input-password" },
            class: "w-full h-10 bg-neutral-2 border border-neutral-8 rounded-[5px] pl-3 pr-10 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
        <button type="button"
                data-action="click->password-visibility#toggle"
                data-testid="auth-button-password-toggle"
                class="absolute right-0 top-0 h-10 w-10 flex items-center justify-center bg-primary-6 rounded-r-[5px] hover:bg-primary-7 focus:outline-none">
          <%# Eye open icon (show password) %>
          <svg data-password-visibility-target="showIcon" class="w-4 h-4 text-white" viewBox="0 0 16 16" fill="currentColor">
            <path d="M8 3C4.364 3 1.258 5.073 0 8c1.258 2.927 4.364 5 8 5s6.742-2.073 8-5c-1.258-2.927-4.364-5-8-5zm0 8.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7zm0-5.5a2 2 0 100 4 2 2 0 000-4z"/>
          </svg>
          <%# Eye closed icon (hide password) %>
          <svg data-password-visibility-target="hideIcon" class="w-4 h-4 text-white hidden" viewBox="0 0 16 16" fill="currentColor">
            <path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 00-2.79.588l.77.771A5.944 5.944 0 018 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0114.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l.708.709z"/>
            <path d="M11.297 9.176a3.5 3.5 0 00-4.474-4.474l.823.823a2.5 2.5 0 012.829 2.829l.822.822zm-2.943 1.299l.822.822a3.5 3.5 0 01-4.474-4.474l.823.823a2.5 2.5 0 002.829 2.829z"/>
            <path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 001.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 018 13.5C3 13.5 0 8 0 8s.939-1.72 2.641-3.238l.708.709z"/>
            <path fill-rule="evenodd" d="M13.646 14.354l-12-12 .708-.708 12 12-.708.708z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    </div>

    <%# Login Button %>
    <div>
      <%= f.submit "Login",
          data: { testid: "auth-button-submit" },
          class: "w-full h-10 bg-primary-6 hover:bg-primary-7 text-white text-sm font-medium rounded-[5px] transition-colors focus:outline-none focus:ring-2 focus:ring-primary-5 focus:ring-offset-2 cursor-pointer" %>
    </div>
  <% end %>

  <%# Links %>
  <div class="flex items-center justify-center gap-0 mt-6">
    <% if devise_mapping.recoverable? %>
      <%= link_to "Forgot Your Password?", new_password_path(resource_name),
          class: "px-2 text-sm text-primary-6 hover:text-primary-7 border-r border-neutral-8",
          data: { testid: "auth-link-forgot-password" } %>
    <% end %>
    <%= link_to "Create an Account!", new_registration_path(resource_name),
        class: "px-2 text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-sign-up" } %>
  </div>

  <div class="flex items-center justify-center mt-4">
    <%= link_to "Need Help?", "#",
        class: "text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-help" } %>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/sessions/new.html.erb
git commit -m "feat(auth): add testid support to login view"
```

---

## Task 2: Registration View (registrations/new)

**Files:**
- Modify: `app/views/devise/registrations/new.html.erb`

**Step 1: Add test IDs to the registration form**

| Element | Test ID |
|---------|---------|
| Container div | `auth-container` |
| Logo image | `auth-logo` |
| Login tab link | `auth-tab-login` |
| Sign Up tab link | `auth-tab-signup` |
| Form element | `auth-form-register` |
| Name input | `auth-input-name` |
| Email input | `auth-input-email` |
| Password input | `auth-input-password` |
| Password confirmation input | `auth-input-password-confirmation` |
| Submit button | `auth-button-submit` |
| Sign in link | `auth-link-sign-in` |
| Need help link | `auth-link-help` |

**Step 2: Apply the changes**

Update `app/views/devise/registrations/new.html.erb`:

```erb
<% content_for(:title) { "Sign Up - QCT InfraScope" } %>

<div class="w-full max-w-[472px] bg-white p-9 shadow-lg" data-testid="auth-container">
  <%# QCT Logo %>
  <div class="flex justify-center py-4">
    <%= image_tag "qct_logo_login.svg", alt: "QCT", class: "h-[94px] w-[340px]", data: { testid: "auth-logo" } %>
  </div>

  <%# Subtitle %>
  <div class="flex justify-center mt-4 mb-6">
    <span class="text-2xl font-bold text-neutral-60">InfraScope</span>
  </div>

  <%# Login / Sign Up Tabs %>
  <div class="flex items-center justify-center gap-2 mb-6">
    <%= link_to "Login", new_user_session_path,
        class: "px-3 py-2 text-sm font-normal text-neutral-60 hover:text-primary-6 border-b-[3px] border-transparent transition-all duration-200",
        data: { testid: "auth-tab-login" } %>
    <%= link_to "Sign Up", new_user_registration_path,
        class: "px-3 py-2 text-sm font-medium text-primary-6 border-b-[3px] border-primary-6 transition-all duration-200",
        data: { testid: "auth-tab-signup" } %>
  </div>

  <%= form_for(resource, as: resource_name, url: registration_path(resource_name), html: { class: "space-y-6", data: { testid: "auth-form-register" } }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <%# Name Field %>
    <div class="space-y-2">
      <label class="block text-sm font-medium text-neutral-60">Name</label>
      <%= f.text_field :name,
          autofocus: true,
          autocomplete: "name",
          placeholder: "Enter your name",
          data: { testid: "auth-input-name" },
          class: "w-full bg-neutral-2 border border-neutral-8 rounded-[5px] p-3 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
    </div>

    <%# Email Field %>
    <div class="space-y-2">
      <label class="block text-sm font-medium text-neutral-60">Email</label>
      <%= f.email_field :email,
          autocomplete: "email",
          placeholder: "Enter email",
          data: { testid: "auth-input-email" },
          class: "w-full bg-neutral-2 border border-neutral-8 rounded-[5px] p-3 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
    </div>

    <%# Password Field %>
    <div class="space-y-2" data-controller="password-visibility">
      <label class="block text-sm font-medium text-neutral-60">Password</label>
      <div class="relative">
        <%= f.password_field :password,
            autocomplete: "new-password",
            placeholder: "Enter password",
            data: { password_visibility_target: "input", testid: "auth-input-password" },
            class: "w-full h-10 bg-neutral-2 border border-neutral-8 rounded-[5px] pl-3 pr-10 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
        <button type="button"
                data-action="click->password-visibility#toggle"
                data-testid="auth-button-password-toggle"
                class="absolute right-0 top-0 h-10 w-10 flex items-center justify-center bg-primary-6 rounded-r-[5px] hover:bg-primary-7 focus:outline-none">
          <svg data-password-visibility-target="showIcon" class="w-4 h-4 text-white" viewBox="0 0 16 16" fill="currentColor">
            <path d="M8 3C4.364 3 1.258 5.073 0 8c1.258 2.927 4.364 5 8 5s6.742-2.073 8-5c-1.258-2.927-4.364-5-8-5zm0 8.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7zm0-5.5a2 2 0 100 4 2 2 0 000-4z"/>
          </svg>
          <svg data-password-visibility-target="hideIcon" class="w-4 h-4 text-white hidden" viewBox="0 0 16 16" fill="currentColor">
            <path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 00-2.79.588l.77.771A5.944 5.944 0 018 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0114.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l.708.709z"/>
            <path d="M11.297 9.176a3.5 3.5 0 00-4.474-4.474l.823.823a2.5 2.5 0 012.829 2.829l.822.822zm-2.943 1.299l.822.822a3.5 3.5 0 01-4.474-4.474l.823.823a2.5 2.5 0 002.829 2.829z"/>
            <path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 001.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 018 13.5C3 13.5 0 8 0 8s.939-1.72 2.641-3.238l.708.709z"/>
            <path fill-rule="evenodd" d="M13.646 14.354l-12-12 .708-.708 12 12-.708.708z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
      <% if @minimum_password_length %>
        <p class="text-xs text-neutral-60"><%= @minimum_password_length %> characters minimum</p>
      <% end %>
    </div>

    <%# Password Confirmation Field %>
    <div class="space-y-2" data-controller="password-visibility">
      <label class="block text-sm font-medium text-neutral-60">Confirm Password</label>
      <div class="relative">
        <%= f.password_field :password_confirmation,
            autocomplete: "new-password",
            placeholder: "Confirm password",
            data: { password_visibility_target: "input", testid: "auth-input-password-confirmation" },
            class: "w-full h-10 bg-neutral-2 border border-neutral-8 rounded-[5px] pl-3 pr-10 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
        <button type="button"
                data-action="click->password-visibility#toggle"
                data-testid="auth-button-password-confirm-toggle"
                class="absolute right-0 top-0 h-10 w-10 flex items-center justify-center bg-primary-6 rounded-r-[5px] hover:bg-primary-7 focus:outline-none">
          <svg data-password-visibility-target="showIcon" class="w-4 h-4 text-white" viewBox="0 0 16 16" fill="currentColor">
            <path d="M8 3C4.364 3 1.258 5.073 0 8c1.258 2.927 4.364 5 8 5s6.742-2.073 8-5c-1.258-2.927-4.364-5-8-5zm0 8.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7zm0-5.5a2 2 0 100 4 2 2 0 000-4z"/>
          </svg>
          <svg data-password-visibility-target="hideIcon" class="w-4 h-4 text-white hidden" viewBox="0 0 16 16" fill="currentColor">
            <path d="M13.359 11.238C15.06 9.72 16 8 16 8s-3-5.5-8-5.5a7.028 7.028 0 00-2.79.588l.77.771A5.944 5.944 0 018 3.5c2.12 0 3.879 1.168 5.168 2.457A13.134 13.134 0 0114.828 8c-.058.087-.122.183-.195.288-.335.48-.83 1.12-1.465 1.755-.165.165-.337.328-.517.486l.708.709z"/>
            <path d="M11.297 9.176a3.5 3.5 0 00-4.474-4.474l.823.823a2.5 2.5 0 012.829 2.829l.822.822zm-2.943 1.299l.822.822a3.5 3.5 0 01-4.474-4.474l.823.823a2.5 2.5 0 002.829 2.829z"/>
            <path d="M3.35 5.47c-.18.16-.353.322-.518.487A13.134 13.134 0 001.172 8l.195.288c.335.48.83 1.12 1.465 1.755C4.121 11.332 5.881 12.5 8 12.5c.716 0 1.39-.133 2.02-.36l.77.772A7.029 7.029 0 018 13.5C3 13.5 0 8 0 8s.939-1.72 2.641-3.238l.708.709z"/>
            <path fill-rule="evenodd" d="M13.646 14.354l-12-12 .708-.708 12 12-.708.708z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    </div>

    <%# Sign Up Button %>
    <div>
      <%= f.submit "Sign Up",
          data: { testid: "auth-button-submit" },
          class: "w-full h-10 bg-primary-6 hover:bg-primary-7 text-white text-sm font-medium rounded-[5px] transition-colors focus:outline-none focus:ring-2 focus:ring-primary-5 focus:ring-offset-2 cursor-pointer" %>
    </div>
  <% end %>

  <%# Links %>
  <div class="flex items-center justify-center mt-6">
    <%= link_to "Already have an account? Sign in", new_session_path(resource_name),
        class: "text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-sign-in" } %>
  </div>

  <div class="flex items-center justify-center mt-4">
    <%= link_to "Need Help?", "#",
        class: "text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-help" } %>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/registrations/new.html.erb
git commit -m "feat(auth): add testid support to registration view"
```

---

## Task 3: Forgot Password View (passwords/new)

**Files:**
- Modify: `app/views/devise/passwords/new.html.erb`

**Step 1: Add test IDs to the forgot password form**

| Element | Test ID |
|---------|---------|
| Container div | `auth-container` |
| Logo image | `auth-logo` |
| Form element | `auth-form-forgot-password` |
| Email input | `auth-input-email` |
| Submit button | `auth-button-submit` |
| Back to login link | `auth-link-sign-in` |
| Create account link | `auth-link-sign-up` |
| Need help link | `auth-link-help` |

**Step 2: Apply the changes**

Update `app/views/devise/passwords/new.html.erb`:

```erb
<% content_for(:title) { "Forgot Password - QCT InfraScope" } %>

<div class="w-full max-w-[472px] bg-white p-9 shadow-lg" data-testid="auth-container">
  <%# QCT Logo %>
  <div class="flex justify-center py-4">
    <%= image_tag "qct_logo_login.svg", alt: "QCT", class: "h-[94px] w-[340px]", data: { testid: "auth-logo" } %>
  </div>

  <%# Subtitle %>
  <div class="flex justify-center mt-4 mb-6">
    <span class="text-2xl font-bold text-neutral-60">InfraScope</span>
  </div>

  <%# Title %>
  <div class="text-center mb-6">
    <h2 class="text-lg font-medium text-neutral-60">Forgot Your Password?</h2>
    <p class="text-sm text-neutral-60 mt-2">Enter your email and we'll send you reset instructions.</p>
  </div>

  <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :post, class: "space-y-6", data: { testid: "auth-form-forgot-password" } }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <%# Email Field %>
    <div class="space-y-2">
      <label class="block text-sm font-medium text-neutral-60">Email</label>
      <%= f.email_field :email,
          autofocus: true,
          autocomplete: "email",
          placeholder: "Enter email",
          data: { testid: "auth-input-email" },
          class: "w-full bg-neutral-2 border border-neutral-8 rounded-[5px] p-3 text-sm text-neutral-60 placeholder:text-neutral-60 focus:outline-none focus:ring-2 focus:ring-primary-5 focus:border-primary-5" %>
    </div>

    <%# Submit Button %>
    <div>
      <%= f.submit "Send Reset Instructions",
          data: { testid: "auth-button-submit" },
          class: "w-full h-10 bg-primary-6 hover:bg-primary-7 text-white text-sm font-medium rounded-[5px] transition-colors focus:outline-none focus:ring-2 focus:ring-primary-5 focus:ring-offset-2 cursor-pointer" %>
    </div>
  <% end %>

  <%# Links %>
  <div class="flex items-center justify-center gap-0 mt-6">
    <%= link_to "Back to Login", new_session_path(resource_name),
        class: "px-2 text-sm text-primary-6 hover:text-primary-7 border-r border-neutral-8",
        data: { testid: "auth-link-sign-in" } %>
    <%= link_to "Create an Account!", new_registration_path(resource_name),
        class: "px-2 text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-sign-up" } %>
  </div>

  <div class="flex items-center justify-center mt-4">
    <%= link_to "Need Help?", "#",
        class: "text-sm text-primary-6 hover:text-primary-7",
        data: { testid: "auth-link-help" } %>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/passwords/new.html.erb
git commit -m "feat(auth): add testid support to forgot password view"
```

---

## Task 4: Reset Password View (passwords/edit)

**Files:**
- Modify: `app/views/devise/passwords/edit.html.erb`

**Step 1: Add test IDs to the reset password form**

| Element | Test ID |
|---------|---------|
| Container card | `auth-container` |
| Form element | `auth-form-reset-password` |
| Password input | `auth-input-password` |
| Password confirmation input | `auth-input-password-confirmation` |
| Submit button | `auth-button-submit` |

**Step 2: Apply the changes**

Update `app/views/devise/passwords/edit.html.erb`:

```erb
<div class="flex min-h-full flex-col justify-center px-6 py-12 lg:px-8">
  <div class="sm:mx-auto sm:w-full sm:max-w-md">
    <div class="card-netbox shadow-xl" data-testid="auth-container">
      <div class="card-header justify-center py-4">
        <h2 class="text-lg font-black text-neutral-85 uppercase tracking-tight">Change your password</h2>
      </div>

      <div class="p-6">
        <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :put, class: "space-y-5", data: { testid: "auth-form-reset-password" } }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>
          <%= f.hidden_field :reset_password_token %>

          <div>
            <%= f.label :password, "New password", class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
            <% if @minimum_password_length %>
              <p class="text-[10px] text-neutral-45 italic mb-2">(<%= @minimum_password_length %> characters minimum)</p>
            <% end %>
            <%= f.password_field :password, autofocus: true, autocomplete: "new-password",
                data: { testid: "auth-input-password" },
                class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
          </div>

          <div>
            <%= f.label :password_confirmation, "Confirm new password", class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
            <%= f.password_field :password_confirmation, autocomplete: "new-password",
                data: { testid: "auth-input-password-confirmation" },
                class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
          </div>

          <div class="pt-2">
            <%= f.submit "Change my password", data: { testid: "auth-button-submit" }, class: "btn-primary w-full justify-center py-2 text-sm" %>
          </div>
        <% end %>

        <div class="mt-6 border-t border-neutral-4 pt-6 text-center">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/passwords/edit.html.erb
git commit -m "feat(auth): add testid support to reset password view"
```

---

## Task 5: Edit Profile View (registrations/edit)

**Files:**
- Modify: `app/views/devise/registrations/edit.html.erb`

**Step 1: Add test IDs to the edit profile form**

| Element | Test ID |
|---------|---------|
| Container card | `auth-container` |
| Form element | `auth-form-edit-profile` |
| Email input | `auth-input-email` |
| Password input | `auth-input-password` |
| Password confirmation input | `auth-input-password-confirmation` |
| Current password input | `auth-input-current-password` |
| Back link | `auth-link-back` |
| Submit button | `auth-button-submit` |
| Danger zone card | `auth-danger-zone` |
| Cancel account button | `auth-button-cancel-account` |

**Step 2: Apply the changes**

Update `app/views/devise/registrations/edit.html.erb`:

```erb
<% content_for(:page_title) { "Edit #{resource_name.to_s.humanize}" } %>

<div class="space-y-6 max-w-2xl">
  <div class="card-netbox" data-testid="auth-container">
    <div class="card-header">
      <h2 class="card-title">Edit Profile</h2>
    </div>

    <div class="p-4">
      <%= form_for(resource, as: resource_name, url: registration_path(resource_name), html: { method: :put, class: "space-y-5", data: { testid: "auth-form-edit-profile" } }) do |f| %>
        <%= render "devise/shared/error_messages", resource: resource %>

        <div>
          <%= f.label :email, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
          <%= f.email_field :email, autofocus: true, autocomplete: "email",
              data: { testid: "auth-input-email" },
              class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
        </div>

        <% if devise_mapping.confirmable? && resource.pending_reconfirmation? %>
          <div class="p-2 bg-primary-1 border border-primary-1 rounded text-xs text-primary-7" data-testid="auth-notice-pending-confirmation">
            Currently waiting confirmation for: <strong><%= resource.unconfirmed_email %></strong>
          </div>
        <% end %>

        <div class="pt-4 border-t border-neutral-4">
          <%= f.label :password, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
          <p class="text-[10px] text-neutral-45 italic mb-2">Leave blank if you don't want to change it</p>
          <%= f.password_field :password, autocomplete: "new-password",
              data: { testid: "auth-input-password" },
              class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
          <% if @minimum_password_length %>
            <p class="mt-1 text-[10px] text-neutral-45"><%= @minimum_password_length %> characters minimum</p>
          <% end %>
        </div>

        <div>
          <%= f.label :password_confirmation, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
          <%= f.password_field :password_confirmation, autocomplete: "new-password",
              data: { testid: "auth-input-password-confirmation" },
              class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
        </div>

        <div class="pt-4 border-t border-neutral-4">
          <%= f.label :current_password, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
          <p class="text-[10px] text-neutral-45 italic mb-2">Required to confirm your changes</p>
          <%= f.password_field :current_password, autocomplete: "current-password",
              data: { testid: "auth-input-current-password" },
              class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
        </div>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-neutral-4">
          <%= link_to "Back", :back, class: "btn-secondary", data: { testid: "auth-link-back" } %>
          <%= f.submit "Update Profile", data: { testid: "auth-button-submit" }, class: "btn-primary" %>
        </div>
      <% end %>
    </div>
  </div>

  <div class="card-netbox border-error-2" data-testid="auth-danger-zone">
    <div class="card-header bg-error-1 border-error-2">
      <h3 class="card-title text-error-8">Danger Zone</h3>
    </div>
    <div class="p-4 flex items-center justify-between">
      <div>
        <p class="text-xs font-bold text-neutral-85">Cancel Account</p>
        <p class="text-[10px] text-neutral-45">Once deleted, your account cannot be recovered.</p>
      </div>
      <%= button_to "Cancel my account", registration_path(resource_name),
          data: { confirm: "Are you sure?", turbo_confirm: "Are you sure?", testid: "auth-button-cancel-account" },
          method: :delete,
          class: "btn-danger" %>
    </div>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/registrations/edit.html.erb
git commit -m "feat(auth): add testid support to edit profile view"
```

---

## Task 6: Shared Error Messages Partial

**Files:**
- Modify: `app/views/devise/shared/_error_messages.html.erb`

**Step 1: Add test IDs to the error messages partial**

| Element | Test ID |
|---------|---------|
| Error container div | `auth-error-message` |

**Step 2: Apply the changes**

Update `app/views/devise/shared/_error_messages.html.erb`:

```erb
<% if resource.errors.any? %>
  <div id="error_explanation"
       data-turbo-cache="false"
       data-testid="auth-error-message"
       class="rounded-none bg-error-1 p-4">
    <div class="flex">
      <div class="flex-shrink-0">
        <%= lucide_icon("circle-x", class: "h-5 w-5 text-error-5") %>
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-error-8">
          <%= I18n.t("errors.messages.not_saved",
                     count: resource.errors.count,
                     resource: resource.class.model_name.human.downcase) %>
        </h3>
        <div class="mt-2 text-sm text-error-7">
          <ul class="list-disc space-y-1 pl-5">
            <% resource.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/shared/_error_messages.html.erb
git commit -m "feat(auth): add testid support to shared error messages"
```

---

## Task 7: Confirmation View (confirmations/new)

**Files:**
- Modify: `app/views/devise/confirmations/new.html.erb`

**Step 1: Add test IDs to the confirmation form**

| Element | Test ID |
|---------|---------|
| Container card | `auth-container` |
| Form element | `auth-form-resend-confirmation` |
| Email input | `auth-input-email` |
| Submit button | `auth-button-submit` |

**Step 2: Apply the changes**

Update `app/views/devise/confirmations/new.html.erb`:

```erb
<div class="flex min-h-full flex-col justify-center px-6 py-12 lg:px-8">
  <div class="sm:mx-auto sm:w-full sm:max-w-md">
    <div class="card-netbox shadow-xl" data-testid="auth-container">
      <div class="card-header justify-center py-4">
        <h2 class="text-lg font-black text-neutral-85 uppercase tracking-tight">Resend confirmation</h2>
      </div>

      <div class="p-6">
        <%= form_for(resource, as: resource_name, url: confirmation_path(resource_name), html: { method: :post, class: "space-y-5", data: { testid: "auth-form-resend-confirmation" } }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>

          <div>
            <%= f.label :email, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email", value: (resource.pending_reconfirmation? ? resource.unconfirmed_email : resource.email),
                data: { testid: "auth-input-email" },
                class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
          </div>

          <div class="pt-2">
            <%= f.submit "Resend instructions", data: { testid: "auth-button-submit" }, class: "btn-primary w-full justify-center py-2 text-sm" %>
          </div>
        <% end %>

        <div class="mt-6 border-t border-neutral-4 pt-6 text-center">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/confirmations/new.html.erb
git commit -m "feat(auth): add testid support to confirmation view"
```

---

## Task 8: Unlock View (unlocks/new)

**Files:**
- Modify: `app/views/devise/unlocks/new.html.erb`

**Step 1: Add test IDs to the unlock form**

| Element | Test ID |
|---------|---------|
| Container card | `auth-container` |
| Form element | `auth-form-resend-unlock` |
| Email input | `auth-input-email` |
| Submit button | `auth-button-submit` |

**Step 2: Apply the changes**

Update `app/views/devise/unlocks/new.html.erb`:

```erb
<div class="flex min-h-full flex-col justify-center px-6 py-12 lg:px-8">
  <div class="sm:mx-auto sm:w-full sm:max-w-md">
    <div class="card-netbox shadow-xl" data-testid="auth-container">
      <div class="card-header justify-center py-4">
        <h2 class="text-lg font-black text-neutral-85 uppercase tracking-tight">Resend unlock instructions</h2>
      </div>

      <div class="p-6">
        <%= form_for(resource, as: resource_name, url: unlock_path(resource_name), html: { method: :post, class: "space-y-5", data: { testid: "auth-form-resend-unlock" } }) do |f| %>
          <%= render "devise/shared/error_messages", resource: resource %>

          <div>
            <%= f.label :email, class: "block text-xs font-bold text-neutral-85 uppercase mb-1" %>
            <%= f.email_field :email, autofocus: true, autocomplete: "email",
                data: { testid: "auth-input-email" },
                class: "block w-full rounded border border-neutral-15 py-1.5 px-3 text-neutral-85 shadow-sm focus:ring-2 focus:ring-primary-5 focus:border-primary-5 sm:text-sm" %>
          </div>

          <div class="pt-2">
            <%= f.submit "Resend instructions", data: { testid: "auth-button-submit" }, class: "btn-primary w-full justify-center py-2 text-sm" %>
          </div>
        <% end %>

        <div class="mt-6 border-t border-neutral-4 pt-6 text-center">
          <%= render "devise/shared/links" %>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/unlocks/new.html.erb
git commit -m "feat(auth): add testid support to unlock view"
```

---

## Task 9: Shared Links Partial

**Files:**
- Modify: `app/views/devise/shared/_links.html.erb`

**Step 1: Add test IDs to the shared links**

| Element | Test ID |
|---------|---------|
| Log in link | `auth-link-sign-in` |
| Sign up link | `auth-link-sign-up` |
| Forgot password link | `auth-link-forgot-password` |
| Resend confirmation link | `auth-link-resend-confirmation` |
| Resend unlock link | `auth-link-resend-unlock` |
| OmniAuth button | `auth-button-oauth-{provider}` |

**Step 2: Apply the changes**

Update `app/views/devise/shared/_links.html.erb`:

```erb
<div class="space-y-2">
  <%- if controller_name != 'sessions' %>
    <%= link_to "Log in", new_session_path(resource_name), class: "block text-xs font-bold text-primary-6 hover:text-primary-7", data: { testid: "auth-link-sign-in" } %>
  <% end %>

  <%- if devise_mapping.registerable? && controller_name != 'registrations' %>
    <%= link_to "Sign up", new_registration_path(resource_name), class: "block text-xs font-bold text-primary-6 hover:text-primary-7", data: { testid: "auth-link-sign-up" } %>
  <% end %>

  <%- if devise_mapping.recoverable? && controller_name != 'passwords' && controller_name != 'registrations' %>
    <%= link_to "Forgot your password?", new_password_path(resource_name), class: "block text-xs font-bold text-primary-6 hover:text-primary-7", data: { testid: "auth-link-forgot-password" } %>
  <% end %>

  <%- if devise_mapping.confirmable? && controller_name != 'confirmations' %>
    <%= link_to "Didn't receive confirmation instructions?", new_confirmation_path(resource_name), class: "block text-xs font-bold text-primary-6 hover:text-primary-7", data: { testid: "auth-link-resend-confirmation" } %>
  <% end %>

  <%- if devise_mapping.lockable? && resource_class.unlock_strategy_enabled?(:email) && controller_name != 'unlocks' %>
    <%= link_to "Didn't receive unlock instructions?", new_unlock_path(resource_name), class: "block text-xs font-bold text-primary-6 hover:text-primary-7", data: { testid: "auth-link-resend-unlock" } %>
  <% end %>

  <%- if devise_mapping.omniauthable? %>
    <%- resource_class.omniauth_providers.each do |provider| %>
      <%= button_to "Sign in with #{OmniAuth::Utils.camelize(provider)}", omniauth_authorize_path(resource_name, provider), data: { turbo: false, testid: "auth-button-oauth-#{provider}" }, class: "btn-secondary w-full justify-center text-xs" %>
    <% end %>
  <% end %>
</div>
```

**Step 3: Verify no syntax errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 4: Commit**

```bash
git add app/views/devise/shared/_links.html.erb
git commit -m "feat(auth): add testid support to shared links partial"
```

---

## Task 10: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

**Step 1: Add auth module section to the reference document**

Append to `docs/testing/test-id-reference.md`:

```markdown

---

## Auth Module (Phase 2)

Auth views use static test IDs since they don't need dynamic prefixes.

### Login View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-logo` | Logo image |
| `auth-tab-login` | Login tab link |
| `auth-tab-signup` | Sign up tab link |
| `auth-flash-alert` | Flash alert message |
| `auth-form-login` | Login form |
| `auth-input-email` | Email input |
| `auth-input-password` | Password input |
| `auth-button-password-toggle` | Password visibility toggle |
| `auth-button-submit` | Submit button |
| `auth-link-forgot-password` | Forgot password link |
| `auth-link-sign-up` | Create account link |
| `auth-link-help` | Need help link |

**Playwright Example:**
```typescript
// Login flow
await page.getByTestId('auth-input-email').fill('user@example.com');
await page.getByTestId('auth-input-password').fill('password123');
await page.getByTestId('auth-button-submit').click();

// Check for error
await expect(page.getByTestId('auth-flash-alert')).toBeVisible();
```

### Registration View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-register` | Registration form |
| `auth-input-name` | Name input |
| `auth-input-email` | Email input |
| `auth-input-password` | Password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-button-submit` | Submit button |
| `auth-link-sign-in` | Sign in link |

### Forgot Password View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-forgot-password` | Forgot password form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |
| `auth-link-sign-in` | Back to login link |
| `auth-link-sign-up` | Create account link |

### Reset Password View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-reset-password` | Reset password form |
| `auth-input-password` | New password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-button-submit` | Submit button |

### Edit Profile View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-edit-profile` | Edit profile form |
| `auth-input-email` | Email input |
| `auth-input-password` | New password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-input-current-password` | Current password input |
| `auth-link-back` | Back link |
| `auth-button-submit` | Submit button |
| `auth-danger-zone` | Danger zone card |
| `auth-button-cancel-account` | Cancel account button |

### Confirmation View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-resend-confirmation` | Resend confirmation form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |

### Unlock View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-resend-unlock` | Resend unlock form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |

### Shared Elements

| Test ID | Element |
|---------|---------|
| `auth-error-message` | Error message container |
| `auth-link-sign-in` | Log in link (shared partial) |
| `auth-link-sign-up` | Sign up link (shared partial) |
| `auth-link-forgot-password` | Forgot password link (shared partial) |
| `auth-link-resend-confirmation` | Resend confirmation link |
| `auth-link-resend-unlock` | Resend unlock link |
| `auth-button-oauth-{provider}` | OmniAuth provider button |
```

**Step 2: Commit**

```bash
git add docs/testing/test-id-reference.md
git commit -m "docs: add auth module test IDs to reference document"
```

---

## Task 11: Run Verification

**Step 1: Verify all views load without errors**

Run: `bin/rails runner "puts 'Views load OK'"`
Expected: No errors

**Step 2: Run rubocop on views**

Run: `bin/rubocop app/views/devise/`
Expected: No offenses (ERB files are not checked by default)

**Step 3: Manual verification (optional)**

Start the development server and visually verify each auth page:
- `/users/sign_in` - Login page
- `/users/sign_up` - Registration page
- `/users/password/new` - Forgot password page
- `/users/confirmation/new` - Resend confirmation page
- `/users/unlock/new` - Resend unlock page

Use browser dev tools to verify `data-testid` attributes are present.

---

## Success Criteria

- [ ] All 8 Devise views have data-testid attributes
- [ ] Shared partials (_error_messages, _links) have data-testid attributes
- [ ] Test ID reference document updated with auth module section
- [ ] All views load without syntax errors
- [ ] Test IDs follow the `auth-{element}-{descriptor}` naming convention

---

## File Summary

| File | Changes |
|------|---------|
| `app/views/devise/sessions/new.html.erb` | Add 13 test IDs |
| `app/views/devise/registrations/new.html.erb` | Add 12 test IDs |
| `app/views/devise/registrations/edit.html.erb` | Add 11 test IDs |
| `app/views/devise/passwords/new.html.erb` | Add 8 test IDs |
| `app/views/devise/passwords/edit.html.erb` | Add 5 test IDs |
| `app/views/devise/confirmations/new.html.erb` | Add 4 test IDs |
| `app/views/devise/unlocks/new.html.erb` | Add 4 test IDs |
| `app/views/devise/shared/_error_messages.html.erb` | Add 1 test ID |
| `app/views/devise/shared/_links.html.erb` | Add 6 test IDs |
| `docs/testing/test-id-reference.md` | Add auth module documentation |
