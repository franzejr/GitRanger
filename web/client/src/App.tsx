function App() {
  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <header className="border-b border-gray-800">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-2xl font-bold">GitNarrate</h1>
          <nav className="flex gap-4">
            <button className="px-4 py-2 rounded-lg bg-gray-800 hover:bg-gray-700 transition-colors">
              Add Repository
            </button>
          </nav>
        </div>
      </header>

      <main className="container mx-auto px-4 py-8">
        <div className="text-center py-16">
          <h2 className="text-4xl font-bold mb-4">
            Narrate Your Git History
          </h2>
          <p className="text-xl text-gray-400 mb-8 max-w-2xl mx-auto">
            AI-powered commit summaries with impact levels, real-time monitoring,
            and beautiful visualizations of your project's evolution.
          </p>
          <button className="px-6 py-3 rounded-lg bg-blue-600 hover:bg-blue-500 font-semibold transition-colors">
            Import Your First Repository
          </button>
        </div>

        <div className="grid md:grid-cols-3 gap-8 mt-12">
          <div className="p-6 rounded-xl bg-gray-800 border border-gray-700">
            <h3 className="text-lg font-semibold mb-2">AI Summaries</h3>
            <p className="text-gray-400">
              Get plain-English explanations of every commit with impact levels
              (patch, minor, major, breaking).
            </p>
          </div>
          <div className="p-6 rounded-xl bg-gray-800 border border-gray-700">
            <h3 className="text-lg font-semibold mb-2">Multiple AI Providers</h3>
            <p className="text-gray-400">
              Choose from Claude Code, Anthropic API, OpenAI, or Ollama for
              fully local analysis.
            </p>
          </div>
          <div className="p-6 rounded-xl bg-gray-800 border border-gray-700">
            <h3 className="text-lg font-semibold mb-2">Real-time Monitoring</h3>
            <p className="text-gray-400">
              Background polling keeps you updated with notifications for new
              commits.
            </p>
          </div>
        </div>
      </main>
    </div>
  )
}

export default App
