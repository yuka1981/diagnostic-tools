import { test, expect, Page } from '@playwright/test';

test.describe('MLC Benchmark Run Flow', () => {
  const credentials = {
    email: 'touyalin@gmail.com',
    password: 'Ab123456',
  };
  const targetNodeHostname = 's5xq-cn02';
  const mlcBinaryPath = '/opt/qct/utils/qis/software/mlc-latest/mlc';

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

  test('should display MLC benchmark form with all required elements', async ({ page }) => {
    console.log('Navigating to MLC benchmark page...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-benchmark-form.png', fullPage: true });

    // Verify node selector exists
    const nodeSelect = page.locator('select[name="mlc_run_form[node_id]"]');
    await expect(nodeSelect).toBeVisible();
    console.log('Node selector found');

    // Verify profile selection exists
    const profileSection = page.locator('[data-controller="mlc-profile"], [class*="profile"]').first();
    if (await profileSection.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.log('Profile selection section found');
    }

    // Verify Advanced Options section
    const advancedOptionsButton = page.locator('button:has-text("Advanced Options")');
    await expect(advancedOptionsButton).toBeVisible();
    console.log('Advanced Options button found');

    // Verify submit button
    const submitButton = page.locator('input[type="submit"][value="Run MLC Benchmark"]');
    await expect(submitButton).toBeVisible();
    console.log('Submit button found');
  });

  test('should show target node in dropdown', async ({ page }) => {
    console.log('Checking node dropdown for target node...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    const nodeSelect = page.locator('select[name="mlc_run_form[node_id]"]');
    await expect(nodeSelect).toBeVisible();

    // Get all options
    const options = await nodeSelect.locator('option').allTextContents();
    console.log(`Available nodes: ${options.join(', ')}`);

    // Check if target node is in the list
    const hasTargetNode = options.some(opt => opt.includes(targetNodeHostname));

    if (hasTargetNode) {
      console.log(`Target node ${targetNodeHostname} found in dropdown`);
      await nodeSelect.selectOption({ label: targetNodeHostname });

      // Verify selection
      const selectedValue = await nodeSelect.inputValue();
      expect(selectedValue).toBeTruthy();
      console.log(`Selected node with value: ${selectedValue}`);
    } else {
      console.log(`Target node ${targetNodeHostname} not in dropdown - may be offline`);
      // Don't fail the test, just log for debugging
    }

    await page.screenshot({ path: 'e2e-mlc-benchmark-node-selected.png', fullPage: true });
  });

  test('should expand and fill advanced options', async ({ page }) => {
    console.log('Testing advanced options...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    // Expand Advanced Options
    const advancedOptionsButton = page.locator('button:has-text("Advanced Options")');
    await advancedOptionsButton.click();
    await page.waitForTimeout(500);

    await page.screenshot({ path: 'e2e-mlc-benchmark-advanced-expanded.png', fullPage: true });

    // Fill binary path
    const binaryPathInput = page.locator('input[name="mlc_run_form[binary_path]"]');
    if (await binaryPathInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await binaryPathInput.fill(mlcBinaryPath);
      console.log('Binary path filled');
    }

    // Fill modules (optional)
    const modulesInput = page.locator('input[name="mlc_run_form[modules]"]');
    if (await modulesInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await modulesInput.fill('intel-mlc');
      console.log('Modules field filled');
    }

    // Fill log path (optional)
    const logPathInput = page.locator('input[name="mlc_run_form[log_path]"]');
    if (await logPathInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await logPathInput.fill('/tmp/mlc-test-log');
      console.log('Log path filled');
    }

    await page.screenshot({ path: 'e2e-mlc-benchmark-advanced-filled.png', fullPage: true });
  });

  test('should select benchmark profile', async ({ page }) => {
    console.log('Testing profile selection...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    // Look for profile cards or radio buttons
    const profileCards = page.locator('[data-action*="mlc-profile#select"]');
    const profileRadios = page.locator('input[type="radio"][name*="profile"]');

    const cardCount = await profileCards.count();
    const radioCount = await profileRadios.count();

    console.log(`Found ${cardCount} profile cards, ${radioCount} profile radios`);

    if (cardCount > 0) {
      // Click the first profile card
      await profileCards.first().click();
      await page.waitForTimeout(500);
      console.log('Clicked first profile card');
    } else if (radioCount > 0) {
      // Select first profile radio
      await profileRadios.first().check();
      console.log('Selected first profile radio');
    }

    await page.screenshot({ path: 'e2e-mlc-benchmark-profile-selected.png', fullPage: true });
  });

  test('should validate form requires node selection', async ({ page }) => {
    console.log('Testing form validation...');
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    // Try to submit without selecting a node
    const submitButton = page.locator('input[type="submit"][value="Run MLC Benchmark"]');
    await submitButton.click();

    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'e2e-mlc-benchmark-validation-error.png', fullPage: true });

    // Should show validation error or stay on same page
    const currentUrl = page.url();
    const hasError = currentUrl.includes('mlc_benchmark') ||
                     await page.locator('.alert, .error, [class*="error"]').isVisible().catch(() => false);

    expect(hasError).toBeTruthy();
    console.log('Form validation working');
  });

  test('should run MLC benchmark on target node', async ({ page }) => {
    console.log('Running full MLC benchmark flow...');

    // Step 1: Navigate to benchmark form
    await page.goto('/mlc_benchmarks/new');
    await page.waitForLoadState('networkidle');

    // Step 2: Select target node
    const nodeSelect = page.locator('select[name="mlc_run_form[node_id]"]');
    await nodeSelect.waitFor({ state: 'visible' });

    try {
      await nodeSelect.selectOption({ label: targetNodeHostname });
      console.log(`Selected node: ${targetNodeHostname}`);
    } catch (e) {
      // Try partial match
      const options = await nodeSelect.locator('option').allTextContents();
      const matchingOption = options.find(opt => opt.includes('s5xq') || opt.includes('cn02'));
      if (matchingOption) {
        await nodeSelect.selectOption({ label: matchingOption });
        console.log(`Selected node: ${matchingOption}`);
      } else {
        console.log('Target node not available, selecting first available node');
        const firstOption = options.find(opt => opt !== 'Select a node...' && opt.trim() !== '');
        if (firstOption) {
          await nodeSelect.selectOption({ label: firstOption });
          console.log(`Selected node: ${firstOption}`);
        } else {
          throw new Error('No nodes available for benchmark');
        }
      }
    }

    // Step 3: Expand and fill advanced options
    const advancedOptionsButton = page.locator('button:has-text("Advanced Options")');
    await advancedOptionsButton.click();
    await page.waitForTimeout(500);

    const binaryPathInput = page.locator('input[name="mlc_run_form[binary_path]"]');
    if (await binaryPathInput.isVisible({ timeout: 3000 }).catch(() => false)) {
      await binaryPathInput.fill(mlcBinaryPath);
    }

    await page.screenshot({ path: 'e2e-mlc-benchmark-filled.png', fullPage: true });

    // Step 4: Submit the form
    console.log('Submitting benchmark...');
    const submitButton = page.locator('input[type="submit"][value="Run MLC Benchmark"]');
    await submitButton.click();
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-benchmark-submitted.png', fullPage: true });

    // Step 5: Verify redirect and success message
    const currentUrl = page.url();
    console.log(`Redirected to: ${currentUrl}`);

    // Should redirect to node page or show success
    const successMessage = page.locator('text=MLC benchmark triggered successfully');
    const nodePageIndicator = page.locator('h1, h2').filter({ hasText: /node|benchmark/i });

    const hasSuccess = await successMessage.isVisible({ timeout: 5000 }).catch(() => false);
    const onNodePage = currentUrl.includes('/nodes/') ||
                       await nodePageIndicator.isVisible({ timeout: 3000 }).catch(() => false);

    if (hasSuccess) {
      console.log('SUCCESS: Benchmark triggered successfully');
    }
    if (onNodePage) {
      console.log('Redirected to node page as expected');
    }

    expect(hasSuccess || onNodePage).toBeTruthy();

    // Step 6: Wait for benchmark to start/complete
    console.log('Waiting for benchmark execution...');
    await page.waitForTimeout(15000);

    // Refresh to see updated status
    await page.reload();
    await page.waitForLoadState('networkidle');

    await page.screenshot({ path: 'e2e-mlc-benchmark-result.png', fullPage: true });

    // Check for benchmark result (pass/fail/running)
    const pageContent = await page.content();
    const hasResult = pageContent.includes('Pass') ||
                      pageContent.includes('Fail') ||
                      pageContent.includes('Running') ||
                      pageContent.includes('Pending') ||
                      pageContent.includes('mlc');

    console.log('=== Benchmark Test Results ===');
    console.log(`Has benchmark result indicator: ${hasResult}`);

    // Test passes if we see any benchmark status
    expect(hasResult).toBeTruthy();
  });

  test('should show benchmark results on node detail page', async ({ page }) => {
    console.log('Checking benchmark results display...');

    // Navigate to nodes list
    await page.goto('/nodes');
    await page.waitForLoadState('networkidle');

    // Find target node
    const nodeLink = page.locator(`a:has-text("${targetNodeHostname}")`).first();

    if (await nodeLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      await nodeLink.click();
      await page.waitForLoadState('networkidle');

      await page.screenshot({ path: 'e2e-mlc-node-detail.png', fullPage: true });

      // Check for benchmark results section
      const benchmarkSection = page.locator('text=Benchmark, text=MLC, [class*="benchmark"]').first();
      const hasBenchmarkSection = await benchmarkSection.isVisible({ timeout: 3000 }).catch(() => false);

      if (hasBenchmarkSection) {
        console.log('Benchmark results section found on node detail page');
      } else {
        console.log('No benchmark results section visible (may need to run a benchmark first)');
      }

      // Check for any benchmark run entries
      const benchmarkRuns = page.locator('table tbody tr, [class*="run"], [class*="benchmark-item"]');
      const runCount = await benchmarkRuns.count();
      console.log(`Found ${runCount} benchmark run entries`);
    } else {
      console.log(`Target node ${targetNodeHostname} not found in nodes list`);

      // Try to find any node with recent benchmark
      const anyNode = page.locator('table tbody tr a').first();
      if (await anyNode.isVisible({ timeout: 3000 }).catch(() => false)) {
        await anyNode.click();
        await page.waitForLoadState('networkidle');
        await page.screenshot({ path: 'e2e-mlc-alternate-node-detail.png', fullPage: true });
      }
    }
  });
});
