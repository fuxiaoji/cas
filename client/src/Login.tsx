// Form structure adapted from 铁底湾 mobile/src/online/AccountPanel.tsx loginView.
import { useState } from 'react';
import type { FormEvent } from 'react';
import { authenticateLocal, lastLocalName } from './account';
import type { LocalProfile } from './account';
import instructor from './assets/harbor/login-instructor.png';
import './login.css';

export function Login({ onLogin }: { onLogin: (profile: LocalProfile) => void }) {
  const [username, setUsername] = useState(lastLocalName);
  const [password, setPassword] = useState('');
  const [register, setRegister] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function authenticate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setError(''); setBusy(true);
    try { onLogin(await authenticateLocal(username, password, register)); }
    catch (err) { setError(err instanceof Error ? err.message : '未能登录，请再试一次。'); }
    finally { setBusy(false); setPassword(''); }
  }
  return <main className="login-screen" aria-label="指挥官登录">
    <header><h1>铁底湾的回响</h1><span>CAS 实时海战</span></header>
    <div className="account-login">
      <div className="account-login-intro">
        <div className="account-login-copy">
          <span className="account-beta-badge">本机航程</span>
          <h3>同一片夜海，<br />新的舰队集结</h3>
          <p>登录后进入母港。舰船、资源和战局随本机指挥官账号保存。</p>
        </div>
        <img src={instructor} alt="编队教官" />
      </div>
      <form onSubmit={event => void authenticate(event)}>
        <h3>{register ? '建立指挥官档案' : '登录舰桥'}</h3>
        <label htmlFor="account-username">用户名</label>
        <input id="account-username" value={username} onChange={e=>setUsername(e.target.value)} autoComplete="username" minLength={3} maxLength={24} required />
        <label htmlFor="account-password">密码</label>
        <input id="account-password" type="password" value={password} onChange={e=>setPassword(e.target.value)} autoComplete={register?'new-password':'current-password'} minLength={10} maxLength={128} required />
        {register && <small>至少 10 个字符。首位指挥官会接续本机已有的 CAS 航程。</small>}
        {error && <p role="alert">{error}</p>}
        <button className="primary" type="submit" disabled={busy}>{busy ? '正在验证…' : register ? '注册并进入母港' : '登录并进入母港'}</button>
        <button type="button" className="quiet" disabled={busy} onClick={()=>{setRegister(v=>!v);setError('');}}>{register?'已有账号，前往登录':'新用户，创建账号'}</button>
      </form>
    </div>
    <footer>本机账号 · 无需联网</footer>
  </main>;
}
