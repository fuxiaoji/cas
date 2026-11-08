import { useEffect, useState } from 'react';
import { onlineRequest } from './online';
import type { OnlineMeta } from './online';
import { claimLocalMail } from './port';
import type { PortState } from './port';
import './mailbox.css';

type Letter = {
  id: string; title: string; body: string; sender: string; created_at?: string; claimed_at?: string | null;
  attachments: { up_tickets: number; standard_tickets: number };
};
type Props = {
  token?: string; state: PortState; change: (reducer: (current: PortState) => PortState) => void;
  onMeta?: (meta: OnlineMeta) => void; onBack: () => void; onRecruit?: () => void;
};

function localLetters(state: PortState): Letter[] {
  return (state.mail ?? []).map(letter => ({
    id: letter.id, title: letter.title, body: letter.body, sender: letter.sender,
    created_at: letter.created ? new Date(letter.created).toISOString() : undefined,
    claimed_at: letter.claimed ? 'local' : null,
    attachments: { up_tickets: letter.up, standard_tickets: letter.standard },
  }));
}

export function Mailbox({ token, state, change, onMeta, onBack, onRecruit }: Props) {
  const [letters, setLetters] = useState<Letter[]>(() => token ? [] : localLetters(state));
  const [busy, setBusy] = useState(!!token);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  async function load() {
    if (!token) { setLetters(localLetters(state)); return; }
    setBusy(true); setError('');
    try {
      const answer = await onlineRequest<{ messages: Letter[] }>('/mail', token);
      setLetters(answer.messages);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '邮箱暂时无法打开。');
    } finally { setBusy(false); }
  }
  useEffect(() => { void load(); }, [token, state.mail]);

  async function claim(letter: Letter) {
    if (busy || letter.claimed_at) return;
    setBusy(true); setError(''); setNotice('');
    try {
      if (token) {
        const answer = await onlineRequest<{ mail: Letter; meta: OnlineMeta }>(`/mail/${encodeURIComponent(letter.id)}/claim`,
          token, { request_id: crypto.randomUUID() });
        onMeta?.(answer.meta);
        setLetters(current => current.map(item => item.id === letter.id ? answer.mail : item));
      } else {
        change(current => claimLocalMail(current, letter.id));
        setLetters(localLetters({ ...state, mail: state.mail?.map(item => item.id === letter.id ? { ...item, claimed: true } : item) }));
      }
      const pull = letter.attachments.standard_tickets + letter.attachments.up_tickets;
      setNotice(`已领取${pull ? ` ${pull} 抽征募补给` : '附件'}。`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '领取失败，请重试。');
    } finally { setBusy(false); }
  }

  const unclaimed = letters.filter(letter => !letter.claimed_at).length;
  return <main className="mailbox" aria-label="邮箱">
    <header className="mailbox-header">
      <button type="button" onClick={onBack}>‹ 返回母港</button>
      <div><span>舰桥通信</span><h1>邮箱</h1></div>
      <span className="mailbox-count">{unclaimed} 封未领取 · {letters.length} 封</span>
    </header>
    <div className="mailbox-body">
      <div className="mailbox-banner">
        <span>内测启航</span>
        <strong>20 抽征募补给</strong>
        <p>新账号的 20 张常驻征募券放在邮箱里，领取后可在「征募与补给」使用。</p>
      </div>
      {error && <p className="mailbox-error" role="alert">{error}</p>}
      {notice && <p className="mailbox-notice" role="status">{notice}</p>}
      {!letters.length && !busy && <p className="mailbox-empty">邮箱是空的。</p>}
      {busy && !letters.length && <p className="mailbox-empty" role="status">正在收取邮件…</p>}
      <ul className="mailbox-list">
        {letters.map(letter => {
          const claimed = !!letter.claimed_at;
          const pull = letter.attachments.up_tickets + letter.attachments.standard_tickets;
          return <li key={letter.id} className={claimed ? 'is-claimed' : ''}>
            <article>
              <header>
                <div><span>{letter.sender}</span><strong>{letter.title}</strong></div>
                <small>{letter.created_at ? new Date(letter.created_at).toLocaleDateString('zh-CN') : '内测'}</small>
              </header>
              <p>{letter.body}</p>
              <footer>
                <span className="mailbox-attachment">
                  {letter.attachments.up_tickets > 0 && <>UP 券 ×{letter.attachments.up_tickets} </>}
                  {letter.attachments.standard_tickets > 0 && <>常驻券 ×{letter.attachments.standard_tickets} </>}
                  {pull > 0 && <b>共 {pull} 抽</b>}
                  {!pull && '无附件'}
                </span>
                <button type="button" disabled={busy || claimed} onClick={() => void claim(letter)}>
                  {claimed ? '已领取' : '领取附件'}
                </button>
              </footer>
            </article>
          </li>;
        })}
      </ul>
      {onRecruit && <button type="button" className="mailbox-recruit" onClick={onRecruit}>前往征募与补给 ›</button>}
    </div>
  </main>;
}
