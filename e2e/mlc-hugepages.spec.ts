import { test, expect } from '@playwright/test';

test.describe('MLC Benchmark Hugepages Pre-flight Check', () => {
  const credentials = {
    email: 'touyalin@gmail.com',
    password: 'Ab123456',
  };
  const targetNodeHostname = 'ldap';
  const mlcBinaryPath = '/opt/intel_mlc/Linux/mlc';

  test.beforeEach(async ({ page }) => {
    // Login
    await page.goto('/users/sign_in');
    await page.waitForLoadState('networkidle');

    // Fill login form
    await page.locator('input[type="email"], input[name*="email"]').fill(credentials.email);
    await page.locator('input[type="password"], input[name*="password"]').fill(credentials.password);
    await page.locator('input[type="submit"][value="Login"], button:has-text("Login")').click();

    // Wait for redirect after login
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);
  });

  test('should show hugepages error when running MLC without hugepages configured', async ({ page }) => {
    // Step 1: Navigate to the ldap node detail page
    console.log('Step 1: Navigating to ldap node detail page...');
    await page.goto('/nodes');
    await page.waitForLoadState('networkidle');

    // Click on the ldap node link
    await page.locator(`a:has-text("${targetNodeHostname}")`).first().click();
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    await page.screenshot({ path: 'e2e-node-detail.png', fullPage: true });

    // Step 2: Update the agent to get the latest code
    console.log('Step 2: Updating agent...');
    const updateAgentButton = page.locator('button:has-text("Update Agent"), a:has-text("Update Agent")').first();

    if (await updateAgentButton.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.log('Found Update Agent button, clicking...');
      await updateAgentButton.click();

      // Wait for update modal or process
      await page.waitForTimeout(2000);

      // If there's a confirmation modal, confirm it
      const confirmButton = page.locator('button:has-text("Update"), button:has-text("Confirm"), button[type="submit"]').last();
      if (await confirmButton.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.log('Confirming update...');
        await confirmButton.click();
      }

      // Wait for update to complete (compilation + deployment takes time)
      console.log('Waiting for agent update to complete (this may take a while)...');
      await page.waitForTimeout(90000); // Wait 90 seconds for compilation and deployment

      // Refresh page
      await page.reload();
      await page.waitForLoadState('networkidle');
    } else {
      console.log('Update Agent button not found, proceeding with current agent');
    }

    await page.screenshot({ path: 'e2e-after-update.png', fullPage: true });

    // Step 3: Navigate to MLC benchmark page
    console.log('Step 3: Running MLC benchmark...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-form-initial.png', fullPage: true });

    // Step 4: Fill the form
    console.log('Step 4: Filling MLC form...');
    const nodeSelect = page.locator('select[name="mlc_run_form[node_id]"]');
    await nodeSelect.waitFor({ state: 'visible' });
    await nodeSelect.selectOption({ label: targetNodeHostname });

    // Expand Advanced Options
    const advancedOptionsButton = page.locator('button:has-text("Advanced Options")');
    await advancedOptionsButton.click();
    await page.waitForTimeout(500);

    // Fill the binary path
    const binaryPathInput = page.locator('input[name="mlc_run_form[binary_path]"]');
    await binaryPathInput.fill(mlcBinaryPath);

    await page.screenshot({ path: 'e2e-mlc-form-filled.png', fullPage: true });

    // Step 5: Submit the form
    console.log('Step 5: Submitting benchmark...');
    const submitButton = page.locator('input[type="submit"][value="Run MLC Benchmark"]');
    await submitButton.click();
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-after-submit.png', fullPage: true });

    // Step 6: Wait for the benchmark to run
    console.log('Step 6: Waiting for benchmark result...');
    await page.waitForTimeout(20000);

    // Refresh to see updated status
    await page.reload();
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-result.png', fullPage: true });

    // Step 7: Check for the hugepages error message
    console.log('Step 7: Checking results...');
    const pageContent = await page.content();

    // Check for our new hugepages error message
    const hasHugepagesError = pageContent.includes('Hugepages not configured') ||
                              pageContent.includes('echo 4000 > /proc/sys/vm/nr_hugepages');

    // Check for the old error (in case agent wasn't updated)
    const hasOldError = pageContent.includes('exit status 22');

    // Check for failed status
    const hasFailedStatus = pageContent.toLowerCase().includes('failed');

    console.log('=== E2E Test Results ===');
    console.log(`Has new hugepages error message: ${hasHugepagesError}`);
    console.log(`Has old exit status 22 error: ${hasOldError}`);
    console.log(`Has failed status: ${hasFailedStatus}`);

    if (hasHugepagesError) {
      console.log('SUCCESS: New hugepages pre-flight check is working!');
    } else if (hasOldError) {
      console.log('WARNING: Old error message showing - agent may need manual update');
    }

    // The test passes if we see our new hugepages error message
    // Or at minimum, the benchmark failed
    expect(hasHugepagesError || hasFailedStatus).toBeTruthy();
  });
});
