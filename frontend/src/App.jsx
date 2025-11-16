import React, {useEffect, useState} from 'react'

function App(){
  const [projections, setProjections] = useState(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  useEffect(()=>{
    fetch('/api/projections')
      .then(r=>r.json())
      .then(j=>setProjections(j))
      .catch(()=>setProjections(null))
      .finally(()=>setLoading(false))
  }, [])

  const refresh = ()=>{
    setRefreshing(true)
    fetch('/api/refresh_projections', {method: 'POST'}).then(()=>{
      // simple optimistic poll to update after a short delay
      setTimeout(()=>{
        fetch('/api/projections')
          .then(r=>r.json()).then(j=>setProjections(j)).finally(()=>setRefreshing(false))
      }, 3000)
    }).catch(()=>setRefreshing(false))
  }

  return (
    <div style={{padding:20}}>
      <h1>NFL Projections</h1>
      <button onClick={refresh} disabled={refreshing}>{refreshing? 'Refreshing...': 'Refresh Projections'}</button>
      {loading && <p>Loading...</p>}
      {!loading && !projections && <p>No projections available</p>}
      {projections && (
        <table border="1" cellPadding="4" style={{marginTop:20}}>
          <thead>
            <tr>
              {Object.keys(projections[0]).slice(0,8).map(k=> <th key={k}>{k}</th>)}
            </tr>
          </thead>
          <tbody>
            {projections.slice(0,50).map((row, idx)=> (
              <tr key={idx}>
                {Object.keys(projections[0]).slice(0,8).map(k=> <td key={k}>{String(row[k])}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

export default App
