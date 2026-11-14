import { ArrowUpRight } from 'lucide-react';
import styles from './ChangelogPage.module.css';

interface ReleaseItem {
  version: string;
  date: string;
  isLatest?: boolean;
  tagline: string;
  sections: {
    title: string;
    items: string[];
  }[];
}

const RELEASES: ReleaseItem[] = [
  {
    version: 'v1.0.0',
    date: 'November 14, 2026',
    isLatest: true,
    tagline: 'Per-Architecture APKs, Verifiable Updates & A Unified Repository',
    sections: [
      {
        title: 'Android Packages',
        items: [
          'Four installable APKs per release: arm64-v8a for modern phones, armeabi-v7a for 32-bit devices, x86_64 for emulators and ChromeOS, and a universal build for every ABI.',
          'A Play Store .aab ships alongside them, and Android 8.0 (API 26) is the enforced floor in Gradle, the release manifest and the updater compatibility gate.',
        ],
      },
      {
        title: 'Verifiable Releases',
        items: [
          'noctra-update-manifest.json pins the filename and SHA-256 of each ABI package, and the in-app updater installs the exact build for your device.',
          'SHA256SUMS.txt covers every published file, with an optional detached signature (noctra-update-manifest.json.sig) when a signing key is configured.',
        ],
      },
      {
        title: 'Repository & Docs',
        items: [
          'Noctra is now published from a single repository at github.com/Ansh22x/Noctra, with every link, updater endpoint and badge pointing at it.',
          'The README and in-repo docs were rewritten around per-ABI downloads, the release pipeline and the updater contract.',
        ],
      },
    ],
  },
];

export function ChangelogPage() {
  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <span className={styles.tag}>RELEASE TIMELINE</span>
        <h1 className={styles.title}>Changelog & Updates</h1>
        <p className={styles.subtitle}>
          Track every release, technical improvement, and audiophile DSP upgrade made to Noctra.
        </p>
      </header>

      <div className={styles.timeline}>
        {RELEASES.map((rel) => (
          <article key={rel.version} className={styles.releaseCard}>
            <div className={styles.releaseHeader}>
              <div className={styles.versionBadgeRow}>
                <span className={styles.versionTag}>{rel.version}</span>
                {rel.isLatest && <span className={styles.latestPill}>Latest Release</span>}
                <time className={styles.releaseDate}>{rel.date}</time>
              </div>
              <h2 className={styles.releaseTagline}>{rel.tagline}</h2>
            </div>

            <div className={styles.sectionsList}>
              {rel.sections.map((sec) => (
                <div key={sec.title} className={styles.sectionBlock}>
                  <h3 className={styles.sectionTitle}>{sec.title}</h3>
                  <ul className={styles.itemList}>
                    {sec.items.map((item, idx) => (
                      <li key={idx} className={styles.itemText}>
                        <span className={styles.bullet}>•</span>
                        <span>{item}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>

            <div className={styles.releaseFooter}>
              <a
                href={`https://github.com/Ansh22x/Noctra/releases/tag/${rel.version}`}
                target="_blank"
                rel="noopener noreferrer"
                className={styles.githubLink}
              >
                <span>View on GitHub Releases</span>
                <ArrowUpRight size={14} />
              </a>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
