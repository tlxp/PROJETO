// --- Módulo: AgentEndpointsTests.cs ---
// Testes de integração dos endpoints HTTP do agente.


using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using VmAgent.Models;
using Xunit;



namespace VmAgent.Tests;



// --- Fábrica de aplicação para testes de integração ---
public sealed class VmAgentWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string TestToken = "test-agent-token-for-ci";



    // --- Configura ambiente de teste com token fixo ---
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        Environment.SetEnvironmentVariable("VM_AGENT_TOKEN", TestToken);
        Environment.SetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE", null);
        builder.UseEnvironment("Development");
    }
}



// --- Testes de integração dos endpoints HTTP ---
public sealed class AgentEndpointsTests : IClassFixture<VmAgentWebApplicationFactory>
{
    private readonly HttpClient _client;



    // --- Injeta cliente HTTP da fábrica de testes ---
    public AgentEndpointsTests(VmAgentWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }



    // --- Health sem token deve devolver 401 ---
    [Fact]
    // --- saúde Without token devolve Unauthorized ---
    public async Task Health_WithoutToken_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/health");



        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }



    // --- Health com token válido deve devolver 200 ---
    [Fact]
    // --- saúde com válido token devolve Ok ---
    public async Task Health_WithValidToken_ReturnsOk()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/health");
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }



    // --- Health com token inválido deve devolver 401 ---
    [Fact]
    // --- saúde com inválido token devolve Unauthorized ---
    public async Task Health_WithInvalidToken_ReturnsUnauthorized()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/health");
        request.Headers.Add("X-Agent-Token", "wrong-token");



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }



    // --- Upload sem multipart deve devolver 400 ---
    [Fact]
    // --- upload Without Multipart devolve Bad pedido ---
    public async Task Upload_WithoutMultipart_ReturnsBadRequest()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/upload");
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);
        request.Content = new StringContent("not-multipart", Encoding.UTF8, "text/plain");



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }



    // --- Upload com ficheiro vazio deve devolver 400 ---
    [Fact]
    // --- upload Empty ficheiro devolve Bad pedido ---
    public async Task Upload_EmptyFile_ReturnsBadRequest()
    {
        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(Array.Empty<byte>());
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        content.Add(fileContent, "file", "empty.bin");



        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/upload") { Content = content };
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }



    // --- Upload com ficheiro válido deve devolver 200 ---
    [Fact]
    // --- upload com válido ficheiro devolve Ok ---
    public async Task Upload_WithValidFile_ReturnsOk()
    {
        using var content = new MultipartFormDataContent();
        var fileBytes = Encoding.UTF8.GetBytes("test payload");
        var fileContent = new ByteArrayContent(fileBytes);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        content.Add(fileContent, "file", "payload.bin");



        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/upload") { Content = content };
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }



    // --- Report antes de execução deve devolver 400 ---
    [Fact]
    // --- relatório Before execução devolve Bad pedido ---
    public async Task Report_BeforeRun_ReturnsBadRequest()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/report");
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);



        var response = await _client.SendAsync(request);



        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }



    // --- Run sem amostra carregada deve devolver 400 ---
    [Fact]
    // --- Executa Without amostra devolve Bad pedido ---
    public async Task Run_WithoutSample_ReturnsBadRequest()
    {
        using var factory = new VmAgentWebApplicationFactory();
        using var client = factory.CreateClient();



        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/run")
        {
            Content = JsonContent.Create(new RunRequest { TimeoutSeconds = 5 })
        };
        request.Headers.Add("X-Agent-Token", VmAgentWebApplicationFactory.TestToken);



        var response = await client.SendAsync(request);



        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}

