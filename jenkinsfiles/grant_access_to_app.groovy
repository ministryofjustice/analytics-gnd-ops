node {

    properties([
        parameters([
            string(
                name: 'APP_NAME',
                description: 'Shiny App name',
                defaultValue: ''),
            string(
                name: 'EMAILS',
                description: 'Semicolon delimited list of email addresses',
                defaultValue: ''),
        ])
    ])

    stage ("Git checkout") {
        checkout scm
    }

    // Creates passwordless user in Auth0 and adds to app group
    // NOTE: Groups provided by Auth0 Authorization Extension
    stage ("Create Auth0 passwordless user and add to app group") {
      withCredentials([
        usernamePassword(
            credentialsId: 'auth0-mgmt-api',
            usernameVariable: 'CLIENT_ID',
            passwordVariable: 'CLIENT_SECRET'),
        string(
            credentialsId: 'authz_api_url',
            variable: 'AUTHZ_API_URL'),
        string(
            credentialsId: 'authz_api_id',
            variable: 'AUTHZ_API_ID'),
        string(
            credentialsId: 'AUTH0_DOMAIN',
            variable: 'AUTH0_DOMAIN')
      ]) {
        sh "/usr/local/bin/grant_access ${env.APP_NAME} ${env.EMAILS}"
      }
    }
}
