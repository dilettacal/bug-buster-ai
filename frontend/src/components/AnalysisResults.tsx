import { AnalysisResultsProps } from '@/types/security';

/**
 * Get color classes for severity badges
 */
function getSeverityColor(severity: string): string {
  switch (severity) {
    case 'critical': return 'text-red-700 bg-red-100';
    case 'high': return 'text-orange-700 bg-orange-100';
    case 'medium': return 'text-yellow-700 bg-yellow-100';
    case 'low': return 'text-green-700 bg-green-100';
    default: return 'text-gray-700 bg-gray-100';
  }
}

/**
 * Analysis results display component with summary and issues table
 */
export default function AnalysisResults({
  analysisResults,
  isAnalyzing,
  error
}: AnalysisResultsProps) {
  return (
    <div className="bg-white rounded-lg border border-border shadow-sm p-6 flex flex-col">
      <h2 className="text-lg font-semibold text-foreground mb-4 flex-shrink-0">
        Results of Analysis
      </h2>
      
      <div className="flex-1 overflow-auto">
        {error && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
            <strong>Error:</strong> {error}
          </div>
        )}
        
        {!analysisResults && !error && (
          <div className="bg-gray-50 rounded-lg border border-border p-4 text-sm text-accent text-center">
            {isAnalyzing ? 'Analyzing code...' : 'Upload and analyze Python code to see security assessment results here.'}
          </div>
        )}
        
        {analysisResults && (
          <div className="space-y-6">
            {/* Summary */}
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <h3 className="font-semibold text-blue-900 mb-2">Analysis Summary</h3>
              <p className="text-blue-800 text-sm">{analysisResults.summary}</p>
            </div>
            
            {/* Issues Table */}
            {analysisResults.issues.length > 0 && (
              <div className="border border-border rounded-lg overflow-hidden">
                <div className="bg-gray-50 px-4 py-3 border-b border-border">
                  <h3 className="font-semibold text-foreground">
                    Security Issues Found ({analysisResults.issues.length})
                  </h3>
                </div>
                
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead className="bg-gray-100">
                      <tr>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          Issue
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          Severity
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          CVSS
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          Description
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          Vulnerable Code
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-gray-700 uppercase tracking-wider">
                          Recommended Fix
                        </th>
                      </tr>
                    </thead>
                    
                    <tbody className="bg-white divide-y divide-gray-200">
                      {analysisResults.issues.map((issue, index) => (
                        <tr key={index} className="hover:bg-gray-50">
                          <td className="px-4 py-4 text-sm font-medium text-gray-900">
                            {issue.title}
                          </td>
                          <td className="px-4 py-4">
                            <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getSeverityColor(issue.severity)}`}>
                              {issue.severity.toUpperCase()}
                            </span>
                          </td>
                          <td className="px-4 py-4 text-sm text-gray-900 font-mono">
                            {issue.cvss_score}
                          </td>
                          <td className="px-4 py-4 text-sm text-gray-700 max-w-xs">
                            {issue.description}
                          </td>
                          <td className="px-4 py-4 text-sm font-mono bg-gray-50 text-red-600 max-w-xs overflow-hidden">
                            <pre className="whitespace-pre-wrap break-words">{issue.code}</pre>
                          </td>
                          <td className="px-4 py-4 text-sm font-mono bg-green-50 text-green-700 max-w-xs overflow-hidden">
                            <pre className="whitespace-pre-wrap break-words">{issue.fix}</pre>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}