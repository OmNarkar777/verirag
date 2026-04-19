import { NavLink } from 'react-router-dom'
import clsx from 'clsx'

const NAV = [
  { to: '/',         label: 'Dashboard',  icon: '⬡' },
  { to: '/pipeline', label: 'Pipeline',   icon: '⟳' },
]

export default function Sidebar() {
  return (
    <aside className="w-56 shrink-0 bg-slate-900 border-r border-slate-800 flex flex-col">
      {/* Logo */}
      <div className="px-5 py-5 border-b border-slate-800">
        <span className="text-xl font-bold tracking-tight">
          <span className="text-brand-500">Veri</span>
          <span className="text-slate-100">RAG</span>
        </span>
        <p className="text-xs text-slate-500 mt-0.5">RAG Eval Platform</p>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-4 space-y-1">
        {NAV.map(({ to, label, icon }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) =>
              clsx(
                'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                isActive
                  ? 'bg-brand-500/20 text-brand-400 border border-brand-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800',
              )
            }
          >
            <span className="text-base leading-none">{icon}</span>
            {label}
          </NavLink>
        ))}
      </nav>

      {/* Footer */}
      <div className="px-5 py-4 border-t border-slate-800">
        <p className="text-xs text-slate-600">RAGAS + Groq + PostgreSQL</p>
      </div>
    </aside>
  )
}
