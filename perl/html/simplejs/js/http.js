"use strict";

function httpPost(sURL, sParams) {

    var oURL = new java.net.URL(sURL);
    var oConnection = oURL.openConnection();

    oConnection.setDoInput(true);
    oConnection.setDoOutput(true);
    oConnection.setUseCaches(false);
    oConnection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");

    var oOutput = new java.io.DataOutputStream(oConnection.getOutputStream());
    oOutput.writeBytes(sParams);
    oOutput.flush();
    oOutput.close();

    var sLine = "", sResponseText = "";

    var oInput = new java.io.DataInputStream(oConnection.getInputStream());
    sLine = oInput.readLine();

    while (sLine != null){
        sResponseText += sLine + "\n";
        sLine = oInput.readLine();
    }

    oInput.close();

    return sResponseText;
}

function addPostParam(sParams, sParamName, sParamValue) {
    if (sParams.length > 0) {
        sParams += "&";
    }
    return sParams + encodeURIComponent(sParamName) + "="
                   + encodeURIComponent(sParamValue);
}

function addURLParam(sURL, sParamName, sParamValue) {
    sURL += (sURL.indexOf("?") == -1 ? "?" : "&");
    sURL += encodeURIComponent(sParamName) + "=" + encodeURIComponent(sParamValue);
    return sURL;
}

function httpGet(sURL) {
    var sResponseText = "";
    var oURL = new java.net.URL(sURL);
    var oStream = oURL.openStream();
    var oReader = new java.io.BufferedReader(new java.io.InputStreamReader(oStream));

    var sLine = oReader.readLine();
    while (sLine != null) {
        sResponseText += sLine + "\n";
        sLine = oReader.readLine();
    }

    oReader.close();
    return sResponseText;
}

var Http = new Object;

Http.get = function (sURL, fnCallback) {

    var oRequest = new XMLHttpRequest();
    oRequest.open("get", sURL, true);
    oRequest.onreadystatechange = function () {
        if (oRequest.readyState == 4) {
            fnCallback(oRequest.responseText);
        }
    }
    oRequest.send(null);
};

Http.post = function (sURL, sParams, fnCallback) {

    var oRequest = new XMLHttpRequest();
    oRequest.open("post", sURL, true);
    oRequest.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    oRequest.onreadystatechange = function () {
        if (oRequest.readyState == 4) {
            fnCallback(oRequest.responseText);
        }
    }
    oRequest.send(sParams);
};
