/**
 * App.jsx — root component: router, layout shell, page routing.
 *
 * Layout: fixed sidebar (256px) + flex-1 main area with header + scrollable content.
 * Error boundary wraps each page so one crashed component can't take down the whole UI.
 */
import { BrowserRouter, Routes, Route, useLocation } from 'react-router-dom'
import { Component } from 'react'
import Sidebar from './components/layout/Sidebar.jsx'
import Header from './components/layout/Header.jsx'
import DashboardPage from './pages/DashboardPage.jsx'
import RunDetailsPage from './pages/RunDetailsPage.jsx'
import PipelinePage from './pages/PipelinePage.jsx'

// Simple error boundary — shows error details + reload button
class ErrorBoundary extends Component {
  state = { error: null }
  static getDerivedStateFromError(error) { return { error } }
  render() {
    if (this.state.error) {
      return (
        <div className="p-8">
          <p className="text-red-400 font-medium mb-2">Something went wrong</p>
          <p className="text-xs text-slate-500 font-mono mb-4">{this.state.error.message}</p>
          <button
            onClick={() => this.setState({ error: null })}
            className="text-xs text-brand-400 hover:text-brand-300 underline"
          >
            Try again
          </button>
        </div>
      )
    }
    return this.props.children
  }
}

const PAGE_META = {
  '/': { title: 'Dashboard', subtitle: 'RAGAS metric trends and eval run history' },
  '/pipeline': { title: 'Pipeline', subtitle: 'Ingest documents · Query · Trigger evaluations' },
}

function Layout() {
  const location = useLocation()
  const isRunDetail = location.pathname.startsWith('/runs/')
  const meta = PAGE_META[location.pathname] ?? {
    title: 'Run Details',
    subtitle: 'Per-case RAGAS scores and regression analysis',
  }

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <Header title={meta.title} subtitle={meta.subtitle} />
        <main className="flex-1 overflow-y-auto">
          <ErrorBoundary>
            <Routes>
              <Route path="/" element={<DashboardPage />} />
              <Route path="/runs/:id" element={<RunDetailsPage />} />
              <Route path="/pipeline" element={<PipelinePage />} />
              <Route path="*" element={
                <div className="p-8 text-center">
                  <p className="text-slate-500">Page not found</p>
                </div>
              } />
            </Routes>
          </ErrorBoundary>
        </main>
      </div>
    </div>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <Layout />
    </BrowserRouter>
  )
}
