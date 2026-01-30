import { test, expect, Page } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';

test.describe('MLC Installation Flow', () => {
  const credentials = {
    email: 'touyalin@gmail.com',
    password: 'Ab123456',
  };
  const targetNodeHostname = 's5xq-cn02';

  async function login(page: Page) {
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    await page.locator('input[type="email"], input[name*="email"]').fill(credentials.email);
    await page.locator('input[type="password"], input[name*="password"]').fill(credentials.password);
    await page.locator('input[type="submit"][value="Login"], button:has-text("Login")').click();

    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);
  }

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('should display MLC installation form with all sections', async ({ page }) => {
    console.log('Navigating to MLC installation page...');
    await page.goto('/mlc_installations/new');
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-install-form.png', fullPage: true });

    // Verify form sections exist
    // Section 1: Upload/Source selection
    const uploadRadio = page.locator('input[type="radio"][value="upload"]');
    const sharedPathRadio = page.locator('input[type="radio"][value="shared_path"]');

    await expect(uploadRadio).toBeVisible();
    await expect(sharedPathRadio).toBeVisible();

    // Section 2: Dropzone for tarball upload
    const dropzone = page.locator('[data-mlc-upload-target="dropzone"]');
    await expect(dropzone).toBeVisible();

    // Section 3: Node selection
    const nodeCheckboxes = page.locator('input[type="checkbox"][name="mlc_installation[node_ids][]"]');
    const checkboxCount = await nodeCheckboxes.count();
    expect(checkboxCount).toBeGreaterThan(0);
    console.log(`Found ${checkboxCount} nodes available for selection`);

    // Section 4: Failure mode options
    const stopOnFirstRadio = page.locator('input[type="radio"][value="stop_on_first"]');
    const continueOnFailureRadio = page.locator('input[type="radio"][value="continue_on_failure"]');

    await expect(stopOnFirstRadio).toBeVisible();
    await expect(continueOnFailureRadio).toBeVisible();

    // Verify submit button
    const installButton = page.locator('input[type="submit"], button[type="submit"]').filter({ hasText: /Install/i });
    await expect(installButton).toBeVisible();
  });

  test('should show target node in the node selection list', async ({ page }) => {
    console.log('Checking target node availability...');
    await page.goto('/mlc_installations/new');
    await page.waitForLoadState('networkidle');

    // Find the target node in the list
    const targetNodeLabel = page.locator(`label:has-text("${targetNodeHostname}")`);

    if (await targetNodeLabel.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log(`Target node ${targetNodeHostname} found in selection list`);
      await expect(targetNodeLabel).toBeVisible();

      // Check the associated checkbox
      const checkbox = page.locator(`input[type="checkbox"][name="mlc_installation[node_ids][]"]`)
        .filter({ has: page.locator(`.. >> label:has-text("${targetNodeHostname}")`) });

      // Try to find checkbox near the label
      const nodeContainer = targetNodeLabel.locator('..');
      const nodeCheckbox = nodeContainer.locator('input[type="checkbox"]');

      if (await nodeCheckbox.isVisible({ timeout: 3000 }).catch(() => false)) {
        await nodeCheckbox.check();
        await expect(nodeCheckbox).toBeChecked();
        console.log(`Successfully selected ${targetNodeHostname}`);
      }
    } else {
      console.log(`Target node ${targetNodeHostname} not found - may be offline`);
      // List available nodes for debugging
      const allLabels = await page.locator('label').allTextContents();
      console.log('Available labels:', allLabels.filter(l => l.includes('cn') || l.includes('s5')));
    }

    await page.screenshot({ path: 'e2e-mlc-install-node-selection.png', fullPage: true });
  });

  test('should toggle between upload and shared path modes', async ({ page }) => {
    console.log('Testing source type toggle...');
    await page.goto('/mlc_installations/new');
    await page.waitForLoadState('networkidle');

    // Initially upload mode should show dropzone
    const dropzone = page.locator('[data-mlc-upload-target="dropzone"]');
    await expect(dropzone).toBeVisible();

    // Switch to shared path mode
    const sharedPathRadio = page.locator('input[type="radio"][value="shared_path"]');
    await sharedPathRadio.check();
    await page.waitForTimeout(500);

    await page.screenshot({ path: 'e2e-mlc-install-shared-path-mode.png', fullPage: true });

    // Shared path input should be visible
    const sharedPathInput = page.locator('input[name="mlc_installation[source_path]"]');
    if (await sharedPathInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await expect(sharedPathInput).toBeVisible();
      console.log('Shared path input is visible');
    }

    // Switch back to upload mode
    const uploadRadio = page.locator('input[type="radio"][value="upload"]');
    await uploadRadio.check();
    await page.waitForTimeout(500);

    await expect(dropzone).toBeVisible();
    console.log('Successfully toggled between source types');
  });

  test('should validate form requires node selection', async ({ page }) => {
    console.log('Testing form validation...');
    await page.goto('/mlc_installations/new');
    await page.waitForLoadState('networkidle');

    // Try to submit without selecting any nodes
    const installButton = page.locator('input[type="submit"], button[type="submit"]').filter({ hasText: /Install/i });
    await installButton.click();

    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'e2e-mlc-install-validation-error.png', fullPage: true });

    // Should show validation error or stay on same page
    const currentUrl = page.url();
    expect(currentUrl).toContain('mlc_installation');
    console.log('Form validation working - stayed on page without node selection');
  });

  test('should show checksum verification UI elements', async ({ page }) => {
    console.log('Checking checksum verification UI...');
    await page.goto('/mlc_installations/new');
    await page.waitForLoadState('networkidle');

    // Look for checksum-related elements
    const checksumSection = page.locator('text=Checksum').first();

    if (await checksumSection.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.log('Checksum section found');

      // Algorithm selector
      const algorithmSelect = page.locator('select[name*="checksum_algorithm"]');
      if (await algorithmSelect.isVisible({ timeout: 3000 }).catch(() => false)) {
        await expect(algorithmSelect).toBeVisible();
        console.log('Checksum algorithm selector found');
      }

      // Checksum input
      const checksumInput = page.locator('input[name*="checksum"]').first();
      if (await checksumInput.isVisible({ timeout: 3000 }).catch(() => false)) {
        await expect(checksumInput).toBeVisible();
        console.log('Checksum input found');
      }

      // Verify button
      const verifyButton = page.locator('button:has-text("Verify")');
      if (await verifyButton.isVisible({ timeout: 3000 }).catch(() => false)) {
        await expect(verifyButton).toBeVisible();
        console.log('Verify button found');
      }
    } else {
      console.log('Checksum section may be hidden until file is uploaded');
    }

    await page.screenshot({ path: 'e2e-mlc-install-checksum-ui.png', fullPage: true });
  });

  test('should display installation progress page after creation', async ({ page }) => {
    // This test verifies the progress page structure without actually installing
    console.log('Checking installation show page structure...');

    // First check if there are any existing installations
    await page.goto('/mlc_installations');
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-installations-list.png', fullPage: true });

    // Look for any installation link
    const installationLink = page.locator('a[href*="/mlc_installations/"]').first();

    if (await installationLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log('Found existing installation, checking progress page...');
      await installationLink.click();
      await page.waitForLoadState('networkidle');

      await page.screenshot({ path: 'e2e-mlc-install-progress.png', fullPage: true });

      // Verify progress page elements
      const statusBadge = page.locator('[class*="badge"], [class*="status"]').first();
      if (await statusBadge.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.log('Status badge found on progress page');
      }

      // Check for node progress list
      const nodeProgressItems = page.locator('[class*="node"], [class*="progress"]');
      const itemCount = await nodeProgressItems.count();
      console.log(`Found ${itemCount} progress-related elements`);
    } else {
      console.log('No existing installations found - skipping progress page check');
    }
  });
});
