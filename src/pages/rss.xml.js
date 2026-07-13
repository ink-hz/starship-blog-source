import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';

const slugOverrides = {
  '交易圣经top5-五本书提炼出的股票交易核心心法': '交易圣经TOP5-五本书提炼出的股票交易核心心法',
};

export async function GET() {
  const posts = await getCollection('blog');
  const publishedPosts = posts
    .filter((post) => !post.data.draft)
    .sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf());

  return rss({
    title: 'Ink Blog',
    description: 'AI、软件架构与机器人智能化探索',
    site: 'http://www.inkbot.cn',
    items: publishedPosts.map((post) => ({
      title: post.data.title,
      description: post.data.description,
      pubDate: post.data.pubDate,
      link: `/blog/${slugOverrides[post.slug] ?? post.slug}/`,
    })),
    customData: '<language>zh-CN</language>',
  });
}
