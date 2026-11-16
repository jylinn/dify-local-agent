# Windows 本地輕量接球異步腳本
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:9999/")
try {
    $listener.Start()
    Write-Host "D槽接球緩衝區已開啟，等候 Dify 數據傳輸..."
    $context = $listener.GetContext()
    $request = $context.Request
    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
    $report = $reader.ReadToEnd()
    
    # 實打實寫入 D 槽
    $today = Get-Date -Format "yyyy-MM-dd"
    $report | Out-File -FilePath "D:\AI_data\forecast_$today.txt" -Encoding utf8
    
    # 優雅回應並自動關閉，絕不霸佔端口
    $response = $context.Response
    $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"status":"Successfully Saved to D Drive"}')
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()
} finally {
    $listener.Stop()
}