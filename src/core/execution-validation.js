const documentationPattern = /(?:^|\/)(?:product|proof)\/|\.(?:md|txt)$/i;
const applePlistDtd = /^http:\/\/www\.apple\.com\/DTDs\/PropertyList-1\.0\.dtd$/;

export function detectRealSideEffects(files = []) {
  const violations = [];
  for (const file of Array.isArray(files) ? files : []) {
    const path = String(file.path || '');
    const content = String(file.content || '');
    if (documentationPattern.test(path)) continue;
    const activeContent = withoutComments(content);
    const urls = [...activeContent.matchAll(/https?:\/\/[^"'\s)>]+/g)].map((match) => match[0]);
    const meaningfulUrls = urls.filter((url) => !(path.endsWith('Info.plist') && applePlistDtd.test(url)));
    if (/stripe\.com|paypal\.com|payment_intents|checkout\.sessions/i.test(activeContent)) {
      violations.push({ kind: 'real_payment', path, detail: '检测到真实支付 endpoint 或 payment API。' });
    }
    if (/upload.*health|health.*upload|cloud.?sync|urlsession|fetch\(/i.test(activeContent) && /health|healthkit/i.test(activeContent)) {
      violations.push({ kind: 'health_data_effect', path, detail: '检测到健康数据网络或上传调用。' });
    }
    if (meaningfulUrls.some((url) => /production|prod\.|\/deploy|\/release/i.test(url)) || /NODE_ENV\s*=\s*production.*(?:deploy|release)/i.test(activeContent)) {
      violations.push({ kind: 'production_effect', path, detail: '检测到生产 endpoint、部署或发布调用。' });
    }
  }
  return violations;
}

function withoutComments(content) {
  return content
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n\r]*/g, '$1')
    .replace(/^\s*#[^\n\r]*/gm, '');
}
