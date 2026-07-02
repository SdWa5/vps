(()=>{var a=Shopware.Classes.ApiService,s=class extends a{constructor(e,r,l="swag-security"){super(e,r,l)}getFixes(){return this.httpClient.get(`_action/${this.getApiBasePath()}/available-fixes`,{headers:this.getBasicHeaders({})}).then(a.handleResponse)}saveValues(e,r){return this.httpClient.post(`_action/${this.getApiBasePath()}/save-config`,{config:e,currentPassword:r},{headers:this.getBasicHeaders({})}).then(a.handleResponse)}cacheClear(){return this.httpClient.delete(`_action/${this.getApiBasePath()}/clear-container-cache`,{headers:this.getBasicHeaders({})}).then(a.handleResponse)}};var i=class{isActive(e){return Shopware.State.get("context").app.config.swagSecurity.includes(e)}};Shopware.Application.addServiceProvider("swagSecurityApi",t=>{let e=Shopware.Application.getContainer("init");return new s(e.httpClient,t.loginService)});Shopware.Application.addServiceProvider("swagSecurityState",()=>new i);var n=`{% block sw_settings_security_index %}
    <sw-page class="sw-settings-security">
        {% block sw_settings_security_search_bar %}
            <template #search-bar>
                <sw-search-bar />
            </template>
        {% endblock %}

        {% block sw_settings_security_smart_bar_header %}
            <template #smart-bar-header>
                {% block sw_settings_security_smart_bar_header_title %}
                    <h2>
                        {% block sw_settings_security_smart_bar_header_title_text %}
                            <span>{{ $tc('sw-settings.index.title') }}</span>

                            <sw-icon
                                name="regular-chevron-right-xs"
                                size="16px"
                            />

                            <span>{{ $tc('sw-settings-security.general.textHeadline') }}</span>
                        {% endblock %}
                    </h2>
                {% endblock %}
            </template>
        {% endblock %}

        {% block sw_settings_security_smart_bar_actions %}
            <template #smart-bar-actions>
                {% block sw_settings_security_actions_save %}
                    <mt-button
                        v-if="fixes?.availableFixes?.length > 0"
                        class="sw-settings-security__save-action"
                        :is-loading="isLoading"
                        variant="primary"
                        @click="onSave"
                    >
                        {{ $tc('sw-settings-security.general.buttonSave') }}
                    </mt-button>
                {% endblock %}
            </template>
        {% endblock %}

        {% block sw_settings_security_content %}
            <template #content>
                <sw-card-view
                    v-if="isLoading || fixes?.availableFixes?.length > 0"
                    class="sw-settings-security__card"
                >
                    <mt-card
                        :title="$tc('sw-settings-security.general.cardTitle')"
                        :is-loading="isLoading"
                    >
                        <mt-banner variant="attention">
                            {{ $tc('sw-settings-security.general.alert') }}
                        </mt-banner>

                        <template
                            v-for="fix in fixes.availableFixes"
                            :key="fix"
                        >
                            <div class="sw-settings-security__fix">
                                <mt-switch
                                    v-model="config[fix]"
                                    class="sw-settings-security__fix-checkbox"
                                    :name="fix"
                                    :label="$tc('sw-settings-security.fixes.' + fix + '.label')"
                                />

                                <div class="sw-settings-security__fix-actions">
                                    <mt-link
                                        as="a"
                                        target="_blank"
                                        type="external"
                                        :href="$tc('sw-settings-security.fixes.' + fix + '.link')"
                                    >
                                        {{ $tc('sw-settings-security.general.advisoryLink') }}
                                    </mt-link>
                                </div>
                            </div>
                        </template>
                    </mt-card>
                </sw-card-view>

                <div
                    v-else
                    class="sw-settings-security__no-fixes-container"
                >
                    <mt-empty-state
                        class="sw-settings-security__no-fixes"
                        icon="regular-lock"
                        :headline="$tc('sw-settings-security.general.noFixesTitle')"
                        :description="$tc('sw-settings-security.general.noFixesDescription')"
                        centered
                    />
                </div>

                <sw-modal
                    v-if="confirmPasswordModal"
                    class="sw-settings-user-detail__confirm-password-modal"
                    :title="$tc('sw-settings-security.modal.placeholderConfirmWithPassword')"
                    variant="small"
                    @modal-close="onCloseConfirmPasswordModal"
                >
                    <mt-password-field
                        v-model="confirmPassword"
                        class="sw-settings-user-detail__confirm-password"
                        required
                        name="sw-field--confirm-password"
                        :password-toggle-able="true"
                        :copy-able="false"
                        :label="$tc('sw-settings-security.modal.labelConfirmWithPassword')"
                        :placeholder="$tc('sw-settings-security.modal.enterPassword')"
                    />

                    <template #modal-footer>
                        <mt-button
                            :disabled="isLoading"
                            size="small"
                            @click="onCloseConfirmPasswordModal"
                        >
                            {{ $tc('sw-settings-security.modal.labelButtonCancel') }}
                        </mt-button>

                        <mt-button
                            variant="primary"
                            :disabled="!confirmPassword"
                            :is-loading="isLoading"
                            size="small"
                            @click="onVerifiedSave"
                        >
                            {{ $tc('sw-settings-security.modal.labelButtonConfirm') }}
                        </mt-button>
                    </template>
                </sw-modal>
            </template>
        {% endblock %}
    </sw-page>
{% endblock %}
`;Shopware.Component.register("sw-settings-security-view",{template:n,mixins:[Shopware.Mixin.getByName("notification")],inject:["swagSecurityApi"],data(){return{isLoading:!1,confirmPasswordModal:!1,confirmPassword:"",config:{},fixes:[]}},async created(){await this.fetchFixes()},methods:{async fetchFixes(){this.isLoading=!0;try{this.fixes=await this.swagSecurityApi.getFixes(),this.config=this.fixes.availableFixes.reduce((t,e)=>(t[e]=this.fixes.activeFixes.includes(e),t),{})}catch{this.createNotificationError({message:this.$tc("sw-settings-security.notification.fetchErrorMessage")})}finally{this.isLoading=!1}},async onVerifiedSave(){this.isLoading=!0;try{await this.swagSecurityApi.saveValues(this.config,this.confirmPassword),this.confirmPasswordModal=!1,this.confirmPassword="",await this.swagSecurityApi.cacheClear(),await this.fetchFixes()}catch{this.createNotificationError({title:this.$tc("sw-settings-security.notification.passwordErrorTitle"),message:this.$tc("sw-settings-security.notification.passwordErrorMessage")})}finally{this.isLoading=!1}},onCloseConfirmPasswordModal(){this.confirmPasswordModal=!1,this.confirmPassword=""},onSave(){this.confirmPasswordModal=!0}}});var o=`{% block sw_settings_content_card_slot_plugins %}
    {% parent %}

    {% block sw_settings_swag_security %}
        <sw-settings-item
            v-if="acl.can('admin')"
            :label="$tc('sw-settings-security.general.mainMenuItemGeneral')"
            :to="{ name: 'sw.settings.security.index' }"
        >
            <template #icon>
                <sw-icon name="regular-shield" />
            </template>
        </sw-settings-item>
    {% endblock %}
{% endblock %}
`;Shopware.Component.override("sw-settings-index",{template:o,inject:["acl"]});var c={type:"plugin",name:"settings-security",title:"sw-settings-security.general.mainMenuItemGeneral",description:"sw-settings-security.general.description",version:"1.0.0",targetVersion:"1.0.0",color:"var(--color-icon-secondary-default)",icon:"regular-cog",favicon:"icon-module-settings.png",routes:{index:{component:"sw-settings-security-view",path:"index",meta:{parentPath:"sw.settings.index",privilege:"admin"}}},settingsItem:[{group:"plugins",to:"sw.settings.security.index",icon:"regular-shield",name:"sw-settings-security.general.mainMenuItemGeneral"}]};Shopware.Component.getComponentRegistry().has("sw-extension-config")||delete c.settingsItem;Shopware.Module.register("sw-settings-security",c);Shopware.Component.override("sw-media-upload-v2",{methods:{handleMediaServiceUploadEvent({action:t,payload:e}){t==="media-upload-fail"&&(this.createNotificationError({title:this.$t("global.default.error"),message:this.getUploadFailureMessage(e)}),this.onRemoveMediaItem())},getUploadFailureMessage(t){let e=t?.error?.response?.data?.errors?.[0]?.detail;return typeof e=="string"&&e.length>0?e:this.$t("global.sw-media-upload-v2.notification.failure.message")}}});})();
