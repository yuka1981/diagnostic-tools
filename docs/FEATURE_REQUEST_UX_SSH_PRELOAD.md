# FEATURE_REQUEST: UX Optimization - Persistent SSH Settings & Auto-Preloading

**Status:** Pending Implementation
**Priority:** Medium (UX Improvement)
**Context:** 目前安裝 Agent 時，使用者每次都需手動輸入複雜的 SSH 與 Bastion 資訊。為了提升 UX，系統應將這些資訊持久化儲存：Bastion 資訊應設為全域設定，而目標節點的 SSH 登入資訊應與 `Node` 資料關聯。安裝頁面開啟時，應自動載入這些預設值。

---

## 1. Requirement Analysis (需求分析)

### 1.1 SSH Configuration Hierarchy (設定層級)

我們將 SSH 連線資訊分為兩個層級管理：

1. **Global Bastion Settings (全域跳板機設定)**:
    * 這是整個 HPC 叢集的入口，通常不會改變。
    * 包含：`Bastion Hostname/IP`, `Bastion User`, `Bastion SSH Port`, `Bastion Key Path` (or Identity File).
    * *Security Note*: Sudo Password 通常不建議明碼儲存，可選擇讓使用者在 Session 中輸入或每次操作時詢問。

2. **Per-Node SSH Settings (個別節點設定)**:
    * 每個運算節點可能會有不同的管理帳號或 Port。
    * 包含：`SSH User` (e.g., root), `SSH Port` (e.g., 22).
    * 這些欄位應直接擴充在 `nodes` 資料表中。

### 1.2 User Story (使用者情境)
>
> 作為管理者，我希望在 "Settings" 頁面設定一次 Bastion 資訊。當我在 "Nodes" 列表點擊某個節點的 "Install Agent" 時，彈出的視窗已經自動填好該節點的 IP、SSH User 以及 Bastion 的連線資訊，我只需要輸入當下的 Sudo 密碼即可開始安裝。

---

## 2. Database & Model Changes

### 2.1 Global Settings (SystemConfig)

我們需要一個地方儲存 Bastion 資訊。可以使用 `Rails.application.credentials` (若不常變動) 或建立一個 `SystemSetting` Model (若需 UI 修改)。這裡採用 **Model 方案** 以符合 "SSH Settings Page" 的需求。

* **Model**: `SshSetting` (Singleton record)
* **Columns**:
  * `bastion_host` (string)
  * `bastion_user` (string)
  * `bastion_port` (integer, default: 22)
  * *(Optional)* `bastion_identity_path` (string) - 若使用統一的 Key

### 2.2 Node Model Update

擴充 `nodes` 表格以紀錄該節點的連線偏好。

* **Model**: `Node`
* **Columns**:
  * `ssh_user` (string, default: 'root') - *New*
  * `ssh_port` (integer, default: 22) - *New*

---

## 3. Web UI Improvements

### 3.1 New Page: SSH Settings

新增一個設定頁面 `/settings/ssh`。

* 提供表單編輯 `SshSetting` 的全域 Bastion 資訊。
* Save 按鈕：更新資料庫中的全域設定。

### 3.2 Update Page: Node Edit

在既有的 "Edit Node" Modal/Page 中加入 SSH 欄位。

* 新增 Input: `SSH User`
* 新增 Input: `SSH Port`

### 3.3 Enhanced Page: Agent Installation Wizard

修改 "Install Agent" 的 Controller Action (`nodes#install_form` or similar)。

* **Backend Logic**:
    1. 讀取目標 `Node` 的資料 (`ip`, `ssh_user`, `ssh_port`)。
    2. 讀取全域 `SshSetting` 的資料 (`bastion_host`, `bastion_user`).
    3. 將這些值傳遞給 View。

* **Frontend Logic**:
    1. 表單欄位預設值 (Default Value) 應填入上述變數。
    2. **Sudo Password** 欄位保持空白 (基於安全考量，或視需求決定是否儲存)。

---

## 4. AI Implementation Prompts (One-Question-One-Answer Style)

Use these prompts to guide the AI in implementing the changes.

### Q1: Database Schema Migration

**Prompt:**
"Act as a Rails Architect.

1. Generate a migration to create a `ssh_settings` table to store global bastion config: `bastion_host`, `bastion_user`, `bastion_port` (int). It should be designed to hold a single record (singleton).
2. Generate a migration to add `ssh_user` and `ssh_port` columns to the `nodes` table. Set default `ssh_port` to 22.
3. Update `Node` model and create a `SshSetting` model (ensure it acts as a singleton)."

### Q2: SSH Settings Page (MVC)

**Prompt:**
"Act as a Fullstack Rails Developer.

1. Create a `Settings::SshController` with `show` and `update` actions.
2. Create a View `app/views/settings/ssh/show.html.erb` using Tailwind CSS. It should allow users to edit the global Bastion Host settings.
3. Ensure the controller fetches the singleton `SshSetting.first_or_create`."

### Q3: Preload Logic for Installation Form

**Prompt:**
"Act as a Rails Developer.

1. Focus on the `NodesController#install_modal` (or the action that renders the install form).
2. Modify the action to fetch:
   * The specific `@node` attributes (`ssh_user`, `ssh_port`).
   * The global `@ssh_setting` attributes (`bastion_host`, `bastion_user`).
3. Update the view (the Install Agent Modal) to use these values as `value="..."` defaults in the input fields.
4. If `ssh_user` is nil in the node, default it to 'root'. If `bastion_host` is configured, pre-fill it; otherwise leave blank."

### Q4: Update Node CRUD

**Prompt:**
"Act as a Rails Developer.

1. Update the `NodesController` strong parameters to permit `ssh_user` and `ssh_port`.
2. Add these two fields to the `_form.html.erb` partial used for New/Edit Node.
3. Use Tailwind CSS to style them neatly."

---

## 5. Definition of Done

* [ ] DB 中有 `ssh_settings` 表與 `nodes` 的新欄位。
* [ ] 使用者可以透過 `/settings/ssh` 設定並儲存跳板機資訊。
* [ ] 新增或編輯 Node 時，可以儲存 `ssh_user`。
* [ ] 點擊 "Install Agent" 時，彈出的視窗會自動填好：
  * Node IP
  * Node SSH User
  * Bastion IP (來自全域設定)
  * Bastion User (來自全域設定)
* [ ] 使用者僅需補上密碼即可送出安裝。
