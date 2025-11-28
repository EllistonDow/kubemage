const urls = (process.env.LHCI_URLS || '')
  .split(/\s+/)
  .map((url) => url.trim())
  .filter(Boolean);

if (!urls.length) {
  throw new Error('Set LHCI_URLS (space or newline separated) before running Lighthouse CI.');
}

const numberOfRuns = parseInt(process.env.LHCI_RUNS || '3', 10);
const preset = process.env.PAGESPEED_LH_PRESET || 'desktop';
const chromeFlags = process.env.PAGESPEED_LH_CHROME_FLAGS || '--no-sandbox --disable-dev-shm-usage';
const minPerfScore = Number(process.env.LHCI_MIN_SCORE || '0.65');
const minA11yScore = Number(process.env.LHCI_A11Y_MIN_SCORE || '0.8');
const minBestPractices = Number(process.env.LHCI_BP_MIN_SCORE || '0.85');
const minSeoScore = Number(process.env.LHCI_SEO_MIN_SCORE || '0.9');
const outputDir = process.env.LHCI_OUTPUT_DIR || 'artifacts/pagespeed/latest';
const method = process.env.LHCI_METHOD || 'psi';

const collect = {
  url: urls,
  numberOfRuns,
  method,
};

if (method === 'psi') {
  collect.psiStrategy = process.env.LHCI_PSI_STRATEGY || 'mobile';
  if (process.env.LHCI_PSI_API_KEY) {
    collect.psiApiKey = process.env.LHCI_PSI_API_KEY;
  }
} else {
  collect.settings = {
    preset,
    chromeFlags,
  };
  if (process.env.LHCI_CHROME_PATH) {
    collect.chromePath = process.env.LHCI_CHROME_PATH;
  }
}

module.exports = {
  ci: {
    collect,
    assert: {
      assertions: {
        'categories:performance': ['warn', { minScore: minPerfScore }],
        'categories:accessibility': ['warn', { minScore: minA11yScore }],
        'categories:best-practices': ['warn', { minScore: minBestPractices }],
        'categories:seo': ['warn', { minScore: minSeoScore }],
      },
    },
    upload: {
      target: 'filesystem',
      outputDir,
    },
  },
};
