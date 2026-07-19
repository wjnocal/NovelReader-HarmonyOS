import { OnlineExtractionRule } from '../model/Models';

export class OnlinePageContent {
  url: string = '';
  bookTitle: string = '';
  title: string = '';
  content: string = '';
  previousUrl: string = '';
  nextUrl: string = '';
  previousChapterUrl: string = '';
  nextChapterUrl: string = '';
  previousPageUrl: string = '';
  nextPageUrl: string = '';
  error: string = '';
}

export class OnlinePageExtractor {
  static buildScript(rule: OnlineExtractionRule): string {
    const customTitle = JSON.stringify(rule.titleSelector);
    const customContent = JSON.stringify(rule.contentSelector);
    const filterPattern = JSON.stringify(rule.filterPattern);
    const nextPageSelector = JSON.stringify(rule.nextPageSelector);
    const nextChapterPattern = JSON.stringify(rule.nextChapterPattern);
    return `(function(){try{
      const customTitle=${customTitle};
      const customContent=${customContent};
      const filterPattern=${filterPattern};
      const nextPageSelector=${nextPageSelector};
      const nextChapterPattern=${nextChapterPattern};
      const one=(s)=>{try{return s?document.querySelector(s):null}catch(e){return null}};
      const clean=(v)=>(v||'').replace(/\\r/g,'').replace(/[ \\t]+\\n/g,'\\n').replace(/\\n[ \\t]+/g,'\\n').replace(/\\n{3,}/g,'\\n\\n').trim();
      const domText=(root)=>{const node=root.cloneNode(true);node.querySelectorAll('br').forEach(e=>e.replaceWith(document.createTextNode('\\n')));node.querySelectorAll('p,dd,li,section,article,blockquote').forEach(e=>e.appendChild(document.createTextNode('\\n')));node.querySelectorAll('div').forEach(e=>{if(!e.querySelector('p,dd,li,section,article,blockquote'))e.appendChild(document.createTextNode('\\n'))});return node.textContent||''};
      const paragraphs=(v)=>{let text=(v||'').replace(/(?:\\u00a0| ){4,}/g,'\\n').replace(/　{2,}/g,'\\n');const lines=text.split(/\\n+/).map(x=>x.replace(/^[ \\t　]+|[ \\t　]+$/g,'')).filter(Boolean);return lines.join('\\n\\n')};
      const titleSelectors=[customTitle,'[itemprop="headline"]','.chapter-title','.chapter_title','#chapter-name h1','#chapter-name h2','.bookname h1','.content h1','article h1','main h1','h1'];
      let title='';for(const s of titleSelectors){const e=one(s);if(e&&clean(e.innerText).length>0){title=clean(e.innerText);break}}
      const selectors=[customContent,'#content','#chaptercontent','#chapterContent','#htmlContent','#booktxt','#txtcontent','#txt','#Lab_Contents','.read-content','.chapter-content','.chapter_content','.row-detail','.yd_text2','.noveltext','article','main'];
      let best=null,bestScore=-1;const seen=new Set();
      for(const s of selectors){if(!s)continue;let list=[];try{list=[...document.querySelectorAll(s)]}catch(e){}for(const e of list){if(seen.has(e))continue;seen.add(e);const t=clean(e.innerText);if(t.length<40)continue;const links=clean([...e.querySelectorAll('a')].map(a=>a.innerText).join('')).length;const score=t.length-links*2+(t.match(/\\n/g)||[]).length*20;if(score>bestScore){best=e;bestScore=score}}}
      if(!best){best=document.body}
      const clone=best.cloneNode(true);clone.querySelectorAll('script,style,noscript,iframe,form,button,nav,.bottem2,.read-page,.page_chapter,.ads,.ad').forEach(e=>e.remove());
      let content=clean(paragraphs(domText(clone)));
      if(filterPattern){try{content=clean(content.replace(new RegExp(filterPattern,'g'),''))}catch(e){}}
      const ad=/^(请记住|最新网址|手机用户|本章未完|一秒记住|天才一秒记住|喜欢本书|加入书签|投推荐票|返回目录|上一章|下一章|上一页|下一页).{0,80}$/;content=clean(paragraphs(content.split('\\n').filter(x=>!ad.test(clean(x))).join('\\n')));
      const absolute=(a)=>{try{return a?new URL(a.getAttribute('href')||'',location.href).href:''}catch(e){return ''}};
      const navigation=()=>{let previousChapter='',nextChapter='',previousPage='',nextPage='',genericPrevious='',genericNext='';const chapterPrev=/^(上一章|上章|上一回|前一章|前章|previous chapter|prev chapter)$/i;const chapterNext=/^(下一章|下章|下一回|后一章|后章|next chapter)$/i;const pagePrev=/^(上一页|上页|previous page|prev page)$/i;const pageNext=/^(下一页|下页|next page)$/i;for(const a of document.querySelectorAll('a[href]')){const text=clean(a.innerText||a.title||a.getAttribute('aria-label'));const id=((a.id||'')+' '+(a.className||'')+' '+(a.rel||'')).toLowerCase();const href=absolute(a);if(!href||href===location.href)continue;if(chapterPrev.test(text))previousChapter=previousChapter||href;if(chapterNext.test(text))nextChapter=nextChapter||href;if(pagePrev.test(text))previousPage=previousPage||href;if(pageNext.test(text))nextPage=nextPage||href;if(/(prevchapter|previouschapter|prev-chapter|prev_chapter|chapter-prev|chapter_previous)/.test(id))previousChapter=previousChapter||href;if(/(nextchapter|next-chapter|next_chapter|chapter-next|chapter_next)/.test(id))nextChapter=nextChapter||href;if(/(prevpage|previouspage|prev-page|prev_page|pager_prev|pb_prev|page-prev)/.test(id))previousPage=previousPage||href;if(/(nextpage|next-page|next_page|pager_next|pb_next|page-next)/.test(id))nextPage=nextPage||href;if(/(^|\\s)(prev|previous)(\\s|$)/.test(id))genericPrevious=genericPrevious||href;if(/(^|\\s)next(\\s|$)/.test(id))genericNext=genericNext||href}if(nextPageSelector){const custom=one(nextPageSelector);const href=absolute(custom);if(href)nextPage=href}if(nextChapterPattern){try{const pattern=new RegExp(nextChapterPattern,'i');if(nextPage&&pattern.test(nextPage)){nextChapter=nextChapter||nextPage;nextPage=''}if(genericNext&&pattern.test(genericNext)){nextChapter=nextChapter||genericNext;genericNext=''}}catch(e){}}if(!previousChapter&&!previousPage)previousChapter=genericPrevious;if(!nextChapter&&!nextPage)nextChapter=genericNext;return {previousChapter,nextChapter,previousPage,nextPage}};
      const nav=navigation();
      const result={url:location.href,bookTitle:clean((one('meta[property="og:novel:book_name"]')||{}).content)||clean((one('meta[property="og:title"]')||{}).content)||clean(document.title).replace(/[_\\-—|｜].*$/,''),title:title||clean(document.title),content:content,previousUrl:nav.previousChapter||nav.previousPage,nextUrl:nav.nextChapter||nav.nextPage,previousChapterUrl:nav.previousChapter,nextChapterUrl:nav.nextChapter,previousPageUrl:nav.previousPage,nextPageUrl:nav.nextPage,error:''};
      return JSON.stringify(result);
    }catch(e){return JSON.stringify({url:location.href,bookTitle:'',title:'',content:'',previousUrl:'',nextUrl:'',previousChapterUrl:'',nextChapterUrl:'',previousPageUrl:'',nextPageUrl:'',error:String(e&&e.message?e.message:e)})}})();`;
  }

  static parse(result: string): OnlinePageContent {
    let value = result.trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      try {
        value = JSON.parse(value) as string;
      } catch (error) {
        // Some Web engine versions already return the JavaScript string value unwrapped.
      }
    }
    const parsed = JSON.parse(value) as OnlinePageContent;
    const output = new OnlinePageContent();
    output.url = parsed.url ?? '';
    output.bookTitle = parsed.bookTitle ?? '';
    output.title = parsed.title ?? '';
    output.content = parsed.content ?? '';
    output.previousUrl = parsed.previousUrl ?? '';
    output.nextUrl = parsed.nextUrl ?? '';
    output.previousChapterUrl = parsed.previousChapterUrl ?? '';
    output.nextChapterUrl = parsed.nextChapterUrl ?? '';
    output.previousPageUrl = parsed.previousPageUrl ?? '';
    output.nextPageUrl = parsed.nextPageUrl ?? '';
    output.error = parsed.error ?? '';
    return output;
  }
}
