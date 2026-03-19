# Open AF Visual Tests

Playwright-based visual regression testing for the Open AF LWC component.

## Setup

1. Install Playwright and browsers:
   ```bash
   npm install -D @playwright/test playwright
   npx playwright install chromium
   ```

2. Set environment variables:
   ```bash
   export SF_USERNAME="your-salesforce-username"
   export SF_PASSWORD="your-salesforce-password"
   export SF_LOGIN_URL="https://login.salesforce.com"  # Optional, default is login.salesforce.com
   export SF_APP_URL="https://your-instance.salesforce.com/lightning/n/Open_AF_Chat"  # Optional
   ```

## Running Tests

### Run all visual tests:
```bash
npm run test:visual
```

### Run tests in headed mode (see browser):
```bash
npm run test:visual:debug
```

### Update baseline screenshots:
```bash
npm run test:visual:update
```

## Test Structure

- `open-af-visual.spec.js`: Main test file with visual regression tests
- `tests/visual/snapshots/`: Directory for baseline and test screenshots
- Tests verify:
  1. Chat interface renders correctly
  2. Sidebar and layout are visible
  3. Input area is functional

## What's Tested

1. **Login Flow**: Navigates to Salesforce and logs in
2. **UI Components**: Verifies sidebar, chat area, and input area exist
3. **Visual Regression**: Takes screenshots for visual comparison
4. **Interaction**: Tests typing in the textarea

## Debugging

- Screenshots are saved to `tests/visual/snapshots/` with timestamps
- Check `debug-current.png` for current page state
- Check `debug-error.png` if navigation fails

## Customization

### Testing Different Environments
Set `SF_APP_URL` to point to different Salesforce instances:
- Production: `https://your-instance.salesforce.com/lightning/n/Open_AF_Chat`
- Sandbox: `https://your-instance--sandbox.salesforce.com/lightning/n/Open_AF_Chat`

### Adding More Tests
Add new test cases to `open-af-visual.spec.js`:
```javascript
test('new visual test', async ({ page }) => {
    // Login and navigate
    await page.goto(loginUrl);
    await page.fill('input[name="username"]', username);
    await page.fill('input[name="pw"]', password);
    await page.click('input[name="Login"]');
    await page.waitForURL('**/lightning/**', { timeout: 30000 });
    
    // Your test logic here
    const element = await page.$('.your-element');
    expect(element).toBeTruthy();
    
    // Take screenshot
    await page.screenshot({ 
        fullPage: true, 
        path: 'tests/visual/snapshots/your-test.png' 
    });
});
```

## CI/CD Integration

Add to your CI pipeline:
```yaml
- name: Run Visual Tests
  env:
    SF_USERNAME: ${{ secrets.SF_USERNAME }}
    SF_PASSWORD: ${{ secrets.SF_PASSWORD }}
  run: |
    npm install -D @playwright/test playwright
    npx playwright install chromium
    npm run test:visual
```

## Notes

- Tests require valid Salesforce credentials
- Screenshots capture the full page for visual regression
- Tests are designed to run in CI environments
- For local development, use `--headed` flag to see the browser
