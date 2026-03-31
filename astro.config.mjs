import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://www.inkbot.cn',
  integrations: [mdx(), sitemap()],
  server: {
    port: 80,
    host: '0.0.0.0'
  },
  markdown: {
    shikiConfig: {
      theme: 'github-light',
      wrap: true
    }
  }
});
